class Home {
    static start() {
        if (document.querySelector("html").offsetWidth < 768) {
            return document
                .querySelector("#theme-css")
                .parentNode.removeChild(document.querySelector("#theme-css"));
        }
        this.cache = {
            items: undefined,
            item: new Map(),
        };
        this.config = new Config();
        this.itemQuery = this.config.itemQuery;
        this.coverOptions = { type: "Backdrop", maxWidth: 3000 };
        this.logoOptions = { type: "Logo", maxWidth: 3000 };
        //this.initStart = true; //1
        //let isRun = false; //0  10
        let isStatic = 2;
        let isLoad = true;
        this.HomeInterval = setInterval(() => {
            if (window.ApiClient != undefined) {
                //获取ApiClientuserView
                if (ApiClient._userViewsPromise != null) {
                    ApiClient._userViewsPromise.then((vlaue) => {
                        let itemId = new Array();
                        vlaue.Items.forEach((item) => {
                            itemId.push(item.Id);
                        });
                        this.config.parentIds = this.config.parentIds.filter((value) =>
                            itemId.includes(value)
                        );
                        //this.initStart = false; //0 00
                        isStatic = isStatic & 1;
                        if (this.config.parentIds.length !== 0) {
                            //isRun = true; //1 01
                            isStatic = isStatic | 1;
                        } else {
                            clearInterval(this.HomeInterval);
                            document
                                .querySelector("#theme-css")
                                .parentNode.removeChild(document.querySelector("#theme-css"));
                            isLoad = false;
                            $(".misty-loading").fadeOut(5, () =>
                                $(".misty-loading").remove()
                            );
                        }
                    });
                }
            }

            if (window.location.href.indexOf("!/home") != -1) {
                const $firstSection = $(".view:not(.hide) .verticalSection.verticalSection-cards").first();
                $firstSection.addClass("section0");
                if (
                    $(".view:not(.hide) .misty-banner").length == 0 &&
                    $(".misty-loading").length == 0
                ) {
                    isStatic = isStatic & 1;
                    if (isLoad) {
                        this.initLoading();
                    }
                }
                if (window.ApiClient == undefined) {
                    //this.initStart = true; //1
                    isStatic = isStatic | 2;
                }
                if (isStatic & (1 == 1) && $(".hide .misty-banner").length != 0) {
                    //1
                    $(".hide .misty-banner").remove();
                }
                if (
                    isStatic == 1 &&
                    $firstSection.length != 0 &&
                    $(".view:not(.hide) .misty-banner").length == 0
                ) {
                    //this.initStart = true; //1 1
                    isStatic = isStatic | 2;
                    this.init();
                }
            } else {
                if ($(".misty-loading").length == 1) {
                    $(".misty-loading").fadeOut(5, () => $(".misty-loading").remove());
                }
            }
        }, 100);
    }

    static async init() {
        // Beta
        $(".view:not(.hide)").attr("data-type", "home");
        // Loading
        const serverName = await this.injectCall("serverName", "");
        $(".misty-loading h1").text(serverName).addClass("active");
        // Banner
        if ($(".view:not(.hide) .misty-banner").length > 0) {
            return $(".view:not(.hide) .misty-banner").length;
        }
        await this.initBanner();
        this.initEvent();
    }

    /* 插入Loading */
    static initLoading() {
        const load = `
		<div class="misty-loading">
			<h1></h1>
			<div class="mdl-spinner"><div class="mdl-spinner__layer mdl-spinner__layer-1"><div class="mdl-spinner__circle-clipper mdl-spinner__left"><div class="mdl-spinner__circle mdl-spinner__circleLeft"></div></div><div class="mdl-spinner__circle-clipper mdl-spinner__right"><div class="mdl-spinner__circle mdl-spinner__circleRight"></div></div></div></div>
		</div>
		`;
        $("body").append(load);
    }

    static injectCode(code) {
        let hash = md5(code + Math.random().toString());
        return new Promise((resolve, reject) => {
            if ("BroadcastChannel" in window) {
                const channel = new BroadcastChannel(hash);
                channel.addEventListener("message", (event) => resolve(event.data));
            } else if ("postMessage" in window) {
                window.addEventListener("message", (event) => {
                    if (event.data.channel === hash) {
                        resolve(event.data.message);
                    }
                });
            }
            const script = `
			<script class="I${hash}">
				setTimeout(async ()=> {
					async function R${hash}(){${code}};
					if ("BroadcastChannel" in window) {
						const channel = new BroadcastChannel("${hash}");
						channel.postMessage(await R${hash}());
					} else if ('postMessage' in window) {
						window.parent.postMessage({channel:"${hash}",message:await R${hash}()}, "*");
					}
					document.querySelector("script.I${hash}").remove()
				}, 16)
			</script>
			`;
            $(document.head || document.documentElement).append(script);
        });
    }

    static injectCall(func, arg) {
        const script = `
		// const client = (await window.require(["ApiClient"]))[0];
		const client = await new Promise((resolve, reject) => {
			setInterval(() => {
				if (window.ApiClient != undefined) resolve(window.ApiClient);
			}, 16);
		});
		return await client.${func}(${arg})
		`;
        return this.injectCode(script);
    }

    static async getItems(query) {
        //由于要合并多个媒体库所以放弃做缓存
        return this.injectCall(
            "getItems",
            "client.getCurrentUserId(), " + JSON.stringify(query)
        );
    }

    static itemsRandom(array) {
        let res = [],
            random;
        while (array.length > 0) {
            random = Math.floor(Math.random() * array.length);
            res.push(array[random]);
            array.splice(random, 1);
        }
        return res;
    }

    static async getItem(itemId) {
        // 双缓存 优先使用 WebStorage
        if (
            typeof Storage !== "undefined" &&
            !localStorage.getItem("CACHE|" + itemId) &&
            !this.cache.item.has(itemId)
        ) {
            const data = JSON.stringify(
                await this.injectCall(
                    "getItem",
                    `client.getCurrentUserId(), "${itemId}"`
                )
            );
            if (typeof Storage !== "undefined")
                localStorage.setItem("CACHE|" + itemId, data);
            else this.cache.item.set(itemId, data);
        }
        return JSON.parse(
            typeof Storage !== "undefined"
                ? localStorage.getItem("CACHE|" + itemId)
                : this.cache.item.get(itemId)
        );
    }

    static getImageUrl(itemId, options) {
        return this.injectCall(
            "getImageUrl",
            itemId + ", " + JSON.stringify(options)
        );
    }

    static async appendItem(i) {
        const detail = await this.getItem(this.data.Items[i].Id),
            itemHtml = `
			<div class="misty-banner-item" id="${detail.Id}">
				<img draggable="false" loading="eager" decoding="async" class="misty-banner-cover" src="${await this.getImageUrl(
                detail.Id,
                this.coverOptions
            )}" alt="Backdrop" style="">
				<div class="misty-banner-info padded-left padded-right">
					<h1>${detail.Name}</h1>
					<div><p>${detail.Overview}</p></div>
					<div><button onclick="appRouter.showItem('${detail.Id}')">MORE</button></div>
				</div>
			</div>
			`,
            logoHtml = `
			<img id="${detail.Id
                }" draggable="false" loading="auto" decoding="lazy" class="misty-banner-logo" data-banner="img-title" alt="Logo" src="${await this.getImageUrl(
                    detail.Id,
                    this.logoOptions
                )}">
			`;
        if (detail.ImageTags && detail.ImageTags.Logo) {
            $(".misty-banner-logos").append(logoHtml);
        }
        $(".misty-banner-body").append(itemHtml);
    }

    static async bannerRoll() {
        if (!window.location.href.endsWith("home")) {
            return;
        }
        // 背景切换
        this.index +=
            this.index + 1 == $(".misty-banner-item").length ? -this.index : 1;
        //已经切换到最后且总数大于10
        if (this.index == 0 && this.data.Items.length >= 10) {
            clearInterval(this.bannerInterval);
            let l = $(".misty-banner-item").length;
            //剩余小于10张直接舍弃，从头开始
            if (
                this.count + 1 == this.data.Items.length ||
                this.data.Items.length - this.count - 1 < 10
            )
                this.count = -1;
            //向后添加,剩余10张以上添加10张
            for (
                let i = this.count + 1;
                i <
                this.count +
                1 +
                (this.data.Items.length - this.count - 1 < 10
                    ? this.data.Items.length - this.count - 1
                    : 10);
                i++
            ) {
                await this.appendItem(i);
            }
            //切换到第一张
            $(".misty-banner-body").css("left", "0%");
            $(".misty-banner-item.active").removeClass("active");
            let id = $(".misty-banner-item").eq(l).addClass("active").attr("id");
            $(".misty-banner-logo.active").removeClass("active");
            $(`.misty-banner-logo[id=${id}]`).addClass("active");
            //从dom中移除上一轮次的横幅
            for (let i = 0; i < l; i++) {
                $(".misty-banner-item").eq(0).remove();
            }
            this.bannerInterval = setInterval(
                this.bannerRoll.bind(this),
                this.config.interval
            );
        } else {
            $(".misty-banner-body").css("left", -(this.index * 100).toString() + "%");
            // 信息切换
            $(".misty-banner-item.active").removeClass("active");
            let id = $(".misty-banner-item")
                .eq(this.index)
                .addClass("active")
                .attr("id");
            // LOGO切换
            $(".misty-banner-logo.active").removeClass("active");
            $(`.misty-banner-logo[id=${id}]`).addClass("active");
        }
        this.count++;
    }

    /* 插入Banner */
    static async initBanner() {
        const banner = `
		<div class="misty-banner">
			<div class="misty-banner-body">
			</div>
			<div class="misty-banner-library">
				<div class="misty-banner-logos"></div>
			</div>
		</div>
		`;
        $(".view:not(.hide) .scrollSlider.sections").first().prepend(banner);
        const items = $(
            ".view:not(.hide) .section0 .emby-scroller .itemsContainer"
        )[0].items;
        $(".view:not(.hide) .section0")
            .detach()
            .appendTo(".view:not(.hide) .misty-banner-library");
        $(".view:not(.hide) .section0 .emby-scroller .itemsContainer")[0].items =
            items;

        // 插入数据
        this.data = { Items: [] };
        //配置的媒体库不为空
        if (this.config.parentIds[0] != "") {
            console.log(this.config.parentIds);
            //合并所有配置的媒体库的结果
            for (let parentId of this.config.parentIds) {
                this.itemQuery.ParentId = parentId;
                let res = await this.getItems(this.itemQuery);
                this.data.Items = this.data.Items.concat(res.Items);
            }
        } else {
            //查询所有媒体库
            this.itemQuery = {
                ImageTypes: "Backdrop",
                EnableImageTypes: "Logo,Backdrop",
                IncludeItemTypes: "Movie,Series",
                SortBy: "ProductionYear, PremiereDate, SortName",
                Recursive: true,
                ImageTypeLimit: 1,
                Limit: 10,
                Fields: "ProductionYear",
                SortOrder: "Descending",
                EnableUserData: false,
                EnableTotalRecordCount: false,
            };
            this.data = await this.getItems(this.itemQuery);
        }

        console.log(this.data);

        if (this.config.random == true) {
            this.data.Items = this.itemsRandom(this.data.Items);
        }
        //大于10时添加10张
        for (
            let i = 0;
            i < (this.data.Items.length < 10 ? this.data.Items.length : 10);
            i++
        ) {
            await this.appendItem(i);
        }

        // 只判断第一张海报加载完毕, 优化加载速度
        await new Promise((resolve, reject) => {
            let waitLoading = setInterval(() => {
                try {
                    if (document.querySelector(".misty-banner-cover").complete) {
                        clearInterval(waitLoading);
                        resolve();
                    }
                } catch (error) {
                    console.log(error);
                    clearInterval(waitLoading);
                    resolve();
                    //clearInterval(this.HomeInterval);
                }
            }, 16);
        });

        $(".misty-loading").fadeOut(500, () => $(".misty-loading").remove());
        await CommonUtils.sleep(150);
        // 置入场动画
        let delay = 80; // 动媒体库画间隔
        let id = $(".misty-banner-item").eq(0).addClass("active").attr("id"); // 初次信息动画
        $(`.misty-banner-logo[id=${id}]`).addClass("active");

        await CommonUtils.sleep(200); // 间隔动画
        $(".section0 > div").addClass("misty-banner-library-overflow"); // 关闭overflow 防止媒体库动画溢出
        $(".misty-banner .card").each((i, dom) =>
            setTimeout(() => $(dom).addClass("misty-banner-library-show"), i * delay)
        ); // 媒体库动画
        await CommonUtils.sleep(delay * 8 + 1000); // 等待媒体库动画完毕
        $(".section0 > div").removeClass("misty-banner-library-overflow"); // 开启overflow 防止无法滚动

        // 滚屏逻辑
        this.index = 0;
        this.count = 0;
        clearInterval(this.bannerInterval);
        this.bannerInterval = setInterval(
            this.bannerRoll.bind(this),
            this.config.interval
        );
    }

    /* 初始事件 */
    static initEvent() {
        // 通过注入方式, 方可调用appRouter函数, 以解决Content-Script window对象不同步问题
        const script = `
		// 挂载appRouter
		if (!window.appRouter) window.appRouter = (await window.require(["appRouter"]))[0];
		// 修复library事件参数
		//const serverId = ApiClient._serverInfo.Id,
		//	librarys = document.querySelectorAll(".view:not(.hide) .section0 .card");
		//librarys.forEach(library => {
		//	library.setAttribute("data-serverid", serverId);
		//	library.setAttribute("data-type", "CollectionFolder");
		//});
		`;
        this.injectCode(script);
    }
}

// 运行
if ("BroadcastChannel" in window || "postMessage" in window) {
    if (
        $("meta[name=application-name]").attr("content") == "Emby" ||
        $(".accent-emby") != undefined
    ) {
        Home.start();
    }
}
