$(function() {
    $("[id^=tnscarousel-]").each(function(){
        var slider = tns({
            container: this,
            controls: true,
            controlsText: ["<i class=\"fa fa-chevron-left\" aria-hidden=\"true\"></i>","<i class=\"fa fa-chevron-right\" aria-hidden=\"true\"></i>"],
            items: 5,
            nav: false,
            gutter: 7.5,
            edgePadding: 5,
            //autoplay: true,
            slideBy: 'page',
            autoplayButton: false,
            autoplayButtonOutput: false,
            autoplayHoverPause: true,
            mouseDrag: false,
            responsive: {
                1700: {
                    "items": 5
                },
                1600: {
                    "items": 5
                },
                1300: {
                    "items": 5
                },
                1100: {
                    "items": 4
                },
                767: {
                    "items": 3
                },
                575: {
                    "items": 3
                },
                320: {
                    "items": 2
                }
            }
        });
        
        $('#bulletins-container').removeClass('hidden');

        var loadCover = function (info, eventName) {
          console.log(info.event.type, info.container.id);
          KOHA.LocalCover.GetCoverFromBibnumber(false);
        }
        slider.events.on('indexChanged', loadCover);

    });
    
});
