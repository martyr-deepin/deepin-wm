##  1.9.25 (2018-05-14)


#### Bug Fixes

*   read cmdline ([5fbec072](5fbec072))
*   quit all modal modes early when grab failed ([ab766f05](ab766f05))
*   quit early when grab failed ([65f9c150](65f9c150))
*   prevent irrelavant keys to navigate ([1946648e](1946648e))
*   disconnect correct callback ([8cdf24fd](8cdf24fd))
*   use client rect to scale thumb ([d1c077b1](d1c077b1))

#### Features

*   auto quit modal mode before sleep ([0bb84ab2](0bb84ab2))
*   register to DDE session manager ([6947d39c](6947d39c))
*   optimize interactive tiling handling ([c45046d1](c45046d1))
*   handle begin_modal grab failure ([84051c29](84051c29))
*   support interactive tiling ([aa8c2edf](aa8c2edf))
*   optimize background caches management ([c903902e](c903902e))
*   toggle blur by enabled flag ([b974ab7a](b974ab7a))
*   activate zone in window overview mode ([92589a84](92589a84))
*   track window add/removal dynamically ([0455fe32](0455fe32))
*   support arrow navigation ([8ac896a7](8ac896a7))
* **tile:**  optimize windows filter ([0d8a6147](0d8a6147))



##  1.9.24 (2018-03-22)


#### Features

*   quit overview if no previews exists ([2d4ebcb1](2d4ebcb1))
*   window overview enhancement ([44f08898](44f08898))

#### Bug Fixes

*   update active background when wallpager changed ([a7039563](a7039563))
*   take care of undergoing window effect ([8018c3d8](8018c3d8))



##  1.9.23 (2018-03-16)


#### Features

*   search icon through desktop file first ([1c8a6efe](1c8a6efe))
*   support wine app icon lookup ([489af07f](489af07f))

#### Bug Fixes

*   check if environ is really opened ([851aa01d](851aa01d))



##  1.9.22 (2018-03-07)


#### Features

*   improve WindowIcon loading ([873699cf](873699cf))
*   set a minimum scaling boundary ([76d9d05c](76d9d05c))

#### Bug Fixes

*   optimize workspace close progress ([4ec86d7a](4ec86d7a))
*   set correct background after reordering ([b6426a2a](b6426a2a))
*   restore dock windows when close ([bd0faf26](bd0faf26))



##  1.9.21 (2017-11-16)


#### Features

*   ui elements adapt to screen scale factor ([b9d013d0](b9d013d0))
*   support flatpak app icon search ([6ba17d09](6ba17d09))

#### Bug Fixes

*   dont show target win from inactive workspace ([2897b5a5](2897b5a5))
*   update system sound name to play it correctly ([fc65b885](fc65b885))



##  1.9.20 (2017-11-09)


#### Bug Fixes

*   break if can not maximize ([82fae120](82fae120))
*   check relative functionality before action ([6a730b59](6a730b59))



##  1.9.19 (2017-11-06)


#### Features

*   make icon operations adapt to scale factor ([39f9c18d](39f9c18d))
*   allow consective tiling ([51a24315](51a24315))



##  (2017-11-01)

#### Features

*   keep actions from interfering each other ([7b127d05](7b127d05))
*   add two dbus operations ([5ea96c58](5ea96c58))
*   hdpi support


