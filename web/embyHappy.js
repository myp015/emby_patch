class EmbyX {
    static regref() {
        let id = JSON.parse(localStorage.servercredentials3).Servers[0].Id;
        if (id != null) {
            let regid = 'regInfo-' + id;
            if (localStorage.getItem(regid + '-viewonly') == null) {
                localStorage.setItem('regInfo-' + id + '-viewonly', '{"lastValidDate":1717208936897,"deviceId":"' + localStorage.getItem('_deviceId2') + '","cacheExpirationDays":365,"lastUpdated":1717208936897}');
            }
            if (localStorage.getItem(regid) == null) {
                localStorage.setItem('regInfo-' + id, '{"lastValidDate":1717208936897,"deviceId":"' + localStorage.getItem('_deviceId2') + '","cacheExpirationDays":365,"lastUpdated":1717208936897}');
            }
        }
    }
}

window.onload = function () {
    EmbyX.regref();
}
