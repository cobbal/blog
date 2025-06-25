{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use section" #-}
{-# HLINT ignore "Avoid lambda using `infix`" #-}

module Main where

import Control.Lens (at, (?~))
import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO)
import Data.Aeson (FromJSON, ToJSON, Value (Object, String), toJSON)
import Data.Aeson.KeyMap (union)
import Data.Aeson.Lens (_Object)
import qualified Data.Text as T
import Data.Time (
  UTCTime,
  defaultTimeLocale,
  formatTime,
  getCurrentTime,
  parseTimeOrError,
 )
import Development.Shake (
  Action,
  Verbosity (Verbose),
  copyFileChanged,
  forP,
  getDirectoryFiles,
  liftIO,
  readFile',
  shakeLintInside,
  shakeOptions,
  shakeVerbosity,
  writeFile',
 )
import Development.Shake.Classes (Binary)
import Development.Shake.FilePath (dropDirectory1, normaliseEx, splitFileName, toStandard, (-<.>), (</>))
import Development.Shake.Forward (cacheAction, shakeArgsForward)
import GHC.Generics (Generic)
import Slick (compileTemplate', convert, markdownToHTML, substitute)
import System.IO (IOMode (WriteMode), hPutStr, withBinaryFile)

---Config-----------------------------------------------------------------------

siteMeta :: SiteMeta
siteMeta =
  SiteMeta
    { siteAuthor = "Andrew Cobb"
    , baseUrl = "https://blog.cobbal.com"
    , siteTitle = "blog.cobbal.com"
    , blueskyHandle = Just "cobbal.bsky.social"
    , mastodonHandle = Just "mstdn.social/@cobbal"
    , githubUser = Just "cobbal"
    }

outputFolder :: FilePath
outputFolder = "docs/"

---Data models------------------------------------------------------------------

withSiteMeta :: Value -> Value
withSiteMeta (Object obj) = Object $ union obj siteMetaObj
  where
    siteMetaObj = unObject (toJSON siteMeta)
    unObject (Object o) = o
    unObject j = error $ "expected Object, got " ++ show j
withSiteMeta _ = error "only add site meta to objects"

data SiteMeta
  = SiteMeta
  { siteAuthor :: String
  , baseUrl :: String -- e.g. https://example.ca
  , siteTitle :: String
  , blueskyHandle :: Maybe String -- Without @
  , mastodonHandle :: Maybe String -- server.com/@handle
  , githubUser :: Maybe String
  }
  deriving (Generic, Eq, Ord, Show, ToJSON)

-- | Data for the index page
data IndexInfo
  = IndexInfo
  { posts :: [Post]
  }
  deriving (Generic, Show, FromJSON, ToJSON)

type Tag = String

-- | Data for a blog post
data Post
  = Post
  { title :: String
  , author :: String
  , content :: String
  , url :: String
  , date :: String
  , tags :: [Tag]
  , description :: String
  , image :: Maybe String
  }
  deriving (Generic, Eq, Ord, Show, FromJSON, ToJSON, Binary)

data AtomData
  = AtomData
  { title :: String
  , domain :: String
  , author :: String
  , posts :: [Post]
  , currentTime :: String
  , atomUrl :: String
  }
  deriving (Generic, ToJSON, Eq, Ord, Show)

-- | given a list of posts this will build a table of contents
buildIndex :: [Post] -> Action ()
buildIndex posts' = do
  indexT <- compileTemplate' "site/templates/index.html"
  let indexInfo = IndexInfo {posts = posts'}
      indexHTML = T.unpack $ substitute indexT (withSiteMeta $ toJSON indexInfo)
  writeBinaryFile' (outputFolder </> "index.html") indexHTML

-- | Find and build all posts
buildPosts :: Action [Post]
buildPosts = do
  pPaths <- getDirectoryFiles "." ["site/posts//*.md"]
  forP pPaths buildPost

{- | Load a post, process metadata, write it to output, then return the post object
Detects changes to either post content or template
-}
buildPost :: FilePath -> Action Post
buildPost srcPath = cacheAction ("build" :: T.Text, srcPath) $ do
  liftIO . putStrLn $ "Rebuilding post: " <> srcPath
  postContent <- readFile' srcPath
  -- load post content and metadata as JSON blob
  postData <- markdownToHTML . T.pack $ postContent
  let postUrl = T.pack . dropDirectory1 $ srcPath -<.> "html"
  let withPostUrl = _Object . at "url" ?~ String (makeWebPath $ "/" ++ T.unpack postUrl)
  -- Add additional metadata we've been able to compute
  let fullPostData = withSiteMeta . withPostUrl $ postData
  template <- compileTemplate' "site/templates/post.html"
  writeBinaryFile' (outputFolder </> T.unpack postUrl) . T.unpack $ substitute template fullPostData
  convert fullPostData

-- | Copy all static files from the listed folders to their destination
copyStaticFiles :: Action ()
copyStaticFiles = do
  filepaths <- getDirectoryFiles "./site/" ["images//*", "css//*", "js//*"]
  void $ forP filepaths $ \filepath ->
    copyFileChanged ("site" </> filepath) (outputFolder </> filepath)

formatDate :: String -> String
formatDate humanDate = toIsoDate parsedTime
  where
    parsedTime =
      parseTimeOrError True defaultTimeLocale "%b %e, %Y" humanDate :: UTCTime

rfc3339 :: Maybe String
rfc3339 = Just "%H:%M:%SZ"

toIsoDate :: UTCTime -> String
toIsoDate = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

dropIndexDotHtml :: FilePath -> FilePath
dropIndexDotHtml path = if fileName == "index.html" then directory else path
  where
    (directory, fileName) = splitFileName path

makeWebPath :: FilePath -> T.Text
makeWebPath = T.pack . toStandard . normaliseEx . dropIndexDotHtml

writeBinaryFile :: FilePath -> String -> IO ()
writeBinaryFile f txt = withBinaryFile f WriteMode (\hdl -> hPutStr hdl txt)

writeBinaryFile' :: (MonadIO m) => FilePath -> String -> m ()
writeBinaryFile' name x = liftIO $ do
  writeFile' name ""
  writeBinaryFile name x

buildFeed :: [Post] -> Action ()
buildFeed posts' = do
  now <- liftIO getCurrentTime
  let atomData =
        AtomData
          { title = siteTitle siteMeta
          , domain = baseUrl siteMeta
          , author = siteAuthor siteMeta
          , posts = mkAtomPost <$> posts'
          , currentTime = toIsoDate now
          , atomUrl = "/atom.xml"
          }
  atomTempl <- compileTemplate' "site/templates/atom.xml"
  writeBinaryFile' (outputFolder </> "atom.xml") . T.unpack $ substitute atomTempl (toJSON atomData)
  where
    mkAtomPost :: Post -> Post
    mkAtomPost p = p {date = formatDate $ date p}

{- | Specific build rules for the Shake system
  defines workflow to build the website
-}
buildRules :: Action ()
buildRules = do
  allPosts <- buildPosts
  buildIndex allPosts
  buildFeed allPosts
  copyStaticFiles

main :: IO ()
main = do
  let shOpts = shakeOptions {shakeVerbosity = Verbose, shakeLintInside = ["\\"]}
  shakeArgsForward shOpts buildRules
