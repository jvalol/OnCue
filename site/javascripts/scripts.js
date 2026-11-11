$(document).ready(function () {

    "use strict";

    // Initialize Smooth Scroll. Only the front page loads the plugin; a call to a plugin that
    // isn't there throws, and everything below it in this handler, the phone menu included,
    // never gets bound.

    if ($.fn.smoothScroll) {
        $('.scroll').smoothScroll({
            offset: -80,
            speed: 1200
        });
    }

    // Mobile Menu Toggle

    $('#mobile-toggle').click(function () {
        if ($('#main-nav').hasClass('open-nav')) {
            $('#main-nav').removeClass('open-nav');
        } else {
            $('#main-nav').addClass('open-nav');
        }
    });

    // Turn dynamic animations for iOS devices (because it doesn't look right)

    var iOS = false,
        p = navigator.platform;

    if (p === 'iPad' || p === 'iPhone' || p === 'iPod') {
        iOS = true;
    }

    // Control Dynamic Content Sliding 

    if (iOS === false) {

        $('.flyIn').bind('inview', function (event, visible) {
            if (visible === true) {
                $(this).addClass('animated fadeInUp');
            }
        });

        $('.flyLeft').bind('inview', function (event, visible) {
            if (visible === true) {
                $(this).addClass('animated fadeInLeftBig');
            }
        });

        $('.flyRight').bind('inview', function (event, visible) {
            if (visible === true) {
                $(this).addClass('animated fadeInRightBig');
            }
        });

    }

    // Handle FAQ Clicks

    $('.question').click(function () {

        if ($(this).siblings('.answer').hasClass('answer-open')) {

            $(this).siblings('.answer').removeClass('answer-open');
            $(this).children('.show-question').removeClass('show-rotate');

        } else {

            $(this).siblings('.answer').addClass('answer-open');
            $(this).children('.show-question').addClass('show-rotate');
        }
    });

    //Contact Form Code:

    $(function () {
        $(".form-send").click(function (e) {
            var $error = 0;
            var email = $(this).siblings(".newsletter-email").val();



            if (email === "") {
                $(this).siblings('.details-error-wrap').fadeIn(1000);
                $error = 1;

            } else {
                $(this).siblings('.details-error-wrap').fadeOut(1000);
				$(this).siblings(".newsletter-email").val('');
            }

            if (!(/(.+)@(.+){2,}\.(.+){2,}/.test(email))) {
                $(this).siblings('.details-error-wrap').fadeIn(1000);
                $error = 1;
            }


            var that = this;
            var dataString = 'email=' + email;
            if ($error === 0) {
                $.ajax({
                    type: "POST",
                    url: "newsletter.php",
                    data: dataString,
                    success: function () {
                        $(that).siblings('.details-error-wrap').fadeOut(300);
                        $(that).fadeOut(500, function () {
                            $(that).siblings('.form-sent').fadeIn(1000);
                        });



                    }
                });
                return false;
            }

            e.preventDefault();
        });
    });



});