let theme = "dark";

function switchTheme() {
    const html = document.getElementsByTagName("html")[0];
    theme = theme === "light" ? "dark" : "light";

    html.classList.remove("light");
    if (theme === "light") {
        html.classList.add("light");
    }

    // Expire in two months
    setCookie("theme", theme, 60 * 24 * 60 * 60 * 1000);

    // const button = document.getElementById("theme-button");
    // button.innerHTML = theme === "dark" ? "Dark" : "Light";
}

function setCookie(cname, cvalue, extime) {
    const d = new Date();
    d.setTime(d.getTime() + (extime));
    const expires = "expires=" + d.toGMTString();
    document.cookie = cname + "=" + cvalue + ";" + expires + ";" + "path=/";
}

function getCookie(cname) {
    const name = cname + "=";
    const ca = document.cookie.split(';');
    for (let i = 0; i < ca.length; i++) {
        const c = ca[i].trim();
        if (c.indexOf(name) === 0) {
            return c.substring(name.length, c.length);
        }
    }
    return "";
}

// Switch theme if cookie is set
if (getCookie('theme') === 'light') {
    switchTheme();
}

// Switch theme if button is clicked.
document.getElementById("theme-button").addEventListener('click', switchTheme);
