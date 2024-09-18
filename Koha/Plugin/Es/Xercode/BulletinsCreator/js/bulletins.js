"use strict";

(function ( $ ) {
    $.fn.createBulletin = function(data) {
        var that = $(this);
        var jsonFilters = null;
        if ($('#userfilters').val() && $('#userfilters').val().length){
            jsonFilters = JSON.parse($('#userfilters').val());
        }
        
        var defaults = {
            format: "grid",
            content: '[{}]'
        };
        data = $.extend({}, defaults, data);
        
        $(this).html("<div class=\"page-loader\"><div class=\"loader\"></div></div>");

        var lastformatused = $('#userfilters').attr('data-defaultview');
        data.format = lastformatused;

        var bulletincontents = $('#bulletincontents').val();
        data.content = bulletincontents;

        var _json = JSON.parse(data.content);
        
        if (data.format == 'grid'){
            $('#btn-bulletin-list').removeClass('hidden');
            $(this).removeAttr("style");
        }else{
            $('#btn-bulletin-grid').removeClass('hidden');
        }

        var cssCards = "bulletin-cards-list";
        var cssCard = "bulletin-card-list";
        if (data.format == 'grid'){
            var cssCards = "bulletin-cards-grid";
            cssCard = "bulletin-card-grid";
        }

        /////////////////////////////
        var sizeau;
        var sizeab;
        var sizeti;
        var markerau;
        var markerab;
        var markerti;

        if ($('#sizeau').val()){
            sizeau = $('#sizeau').val();
        } else {
            sizeau = 20; 
        }

        if ($('#sizeab').val()){
            sizeab = $('#sizeab').val();
        } else {
            sizeab = 300; 
        }

        if ($('#sizeti').val()){
            sizeti = $('#sizeti').val();
        } else {
            sizeti = 25; 
        }

        if ($('#markerau').val()){
            markerau = $('#markerau').val();
        } else {
            markerau = '...'; 
        }

        if ($('#markerab').val()){
            markerab = $('#markerab').val();
        } else {
            markerab = '...'; 
        }

        if ($('#markerti').val()){
            markerti = $('#markerti').val();
        } else {
            markerti = '...';
        }
        /////////////////////////////
        
        var content = "<div class='"+cssCards+"'>";
        var iterator = 0;
        $(_json.contents).each( function (index, row){
            // Metadata
            var image = "";
            if (row.isbn){
                var source = 'https://images-na.ssl-images-amazon.com/images/P/'+row.isbn+'.jpg';
                image ="<img src='"+source+"' alt='Amazon cover image' />";
            }else{
                image = "<span title=\""+row.title+"\" class=\""+row.biblionumber+"\" id=\"local-thumbnail-"+index+"\"></span>";
            }
            var title = row.title;
            if (data.format == 'grid' && row.title.length > sizeti) {
                title = row.title.substring(0,sizeti).trim() + markerti;
            }
            var author = "&nbsp;";
            if (row.author != 'null' && row.author != null && row.author.length > 0) {
                if (row.author.length > sizeau) {
                    author = row.author.substring(0,sizeau).trim() + markerau;
                } else {
                    author = row.author;
                }
                author = MSG_BY + " " + author;
            }
            var abstract = "";
            var abstract_final = "";
            if (row.abstract != 'null' && row.abstract != null) {
                var _abstracttext = "";
                if (row.abstract.length > sizeab) {
                    abstract_final = row.abstract.split("\n").join("");
                    _abstracttext = abstract_final.replace(new RegExp("^(.{"+sizeab+"}[^\\s]*).*"), "$1") + markerab;
                    if (_json.iteminfo){
                        _abstracttext = abstract_final.replace(new RegExp("^(.{"+sizeab+"}[^\\s]*).*"), "$1") + markerab; 
                    }
                } else {
                    _abstracttext = row.abstract;
                }
                var hideAbstract = "";
                if (data.format == 'grid'){
                    hideAbstract = " hidden"
                }
                abstract = "<div class='data-abstract" + hideAbstract + "'>" + _abstracttext + "</div>";
            }

            // Filters
            var format = "";
            if (row.format != 'null' && row.format != null) {
                format = row.format;
            }
            var language = "";
            if (row.language != 'null' && row.language != null) {
                language = row.language;
            }
            var year = "";
            if (row.publicationyear != 'null' && row.publicationyear != null) {
                year = row.publicationyear;
            }

            // User filters
            if (jsonFilters != null){
                var hideme = false;
                $(jsonFilters).each(function(_index, _row){
                    if (_row.format !== undefined && _row.format.length > 0 && _row.format[0].length > 0 && (_row.format.indexOf(format) === -1)){
                        hideme = true;
                    }
                    if (_row.language !== undefined && _row.language.length > 0 && _row.language[0].length > 0 && (_row.language.indexOf(language) === -1)){
                        hideme = true;
                    }
                    if (_row.year !== undefined && _row.year.length > 0 && _row.year[0].length > 0 && (_row.year.indexOf(year) === -1)){
                        hideme = true;
                    }
                });
                if (hideme){
                    return true;
                }
            }
            // END

            var format_text = format;
            if ((eval('typeof MSG_FORMAT_' + format)) !== "undefined"){
                format_text = eval('MSG_FORMAT_' + format);
            }
            
            content += "<div class='bulletin-card "+cssCard+"' style='display: none' data-format='"+format+"' data-language='"+language+"' data-year='"+year+"'>";
            content += "        <div class=\"thumb\">";
            content += "             <a href='/cgi-bin/koha/opac-detail.pl?biblionumber="+row.biblionumber+"' target='_blank'>";
            content +=                   image;
            content += "             </a>";
            content += "        </div>";
            content += "        <span class=\"data\">";
            content += "            <div class='data-title'><a href='/cgi-bin/koha/opac-detail.pl?biblionumber="+row.biblionumber+"' target='_blank'>" + title + "</a></div>";
            content += "            <div class='data-author'>" + author + "</div>";
            content += "            <div class='data-format'><i class='fa " + row.formaticon + "'></i>" + "<span>" + format_text + "</span></div>";
            content +=             abstract;
            content += "        </span>";
            content += "</div>";
            
            iterator++;    
        });
        
        content += "</div>";
        
        if (iterator === 0){
            content += "<div class='alert alert-info text-center'>" + MSG_BULLETIN_NO_CONTENTS + "</div>";
        }
        
        this.append(content);
        KOHA.LocalCover.GetCoverFromBibnumber(false);
        
        setTimeout(function(){
            $(that).find('.page-loader').remove();
            $(that).find('.'+cssCard+'').show('slow');
        }, 1000);
        
    };
}( jQuery ));

function bulletinSwitchView(view){
    if (view == 'grid'){
        $('#bulletin').find('.bulletin-cards-list').toggleClass('bulletin-cards-list bulletin-cards-grid').show('slow');
        $('#bulletin').find('.bulletin-card-list').toggleClass('bulletin-card-list bulletin-card-grid').show('slow');
        $('#bulletin').find('.bulletin-card-grid .data-abstract').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-grid .data-itemtype').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-grid .data-location_description').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-grid .data-itemcallnumber').toggleClass('hidden');
    }else{
        $('#bulletin').find('.bulletin-cards-grid').toggleClass('bulletin-cards-grid bulletin-cards-list').show('slow');
        $('#bulletin').find('.bulletin-card-grid').toggleClass('bulletin-card-grid bulletin-card-list').show('slow');
        $('#bulletin').find('.bulletin-card-list .data-abstract').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-list .data-itemtype').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-list .data-location_description').toggleClass('hidden');
        $('#bulletin').find('.bulletin-card-list .data-itemcallnumber').toggleClass('hidden');
    }
}

function saveApplyFilters(){
    var jsonObj = [];

    var format = [];
    $('#bulletinmodalfilters .filter-format input[type=radio]').each(function (){
        if ($(this).prop('checked')){
            format.push($(this).val());
        }
    });
    jsonObj.push({'format':format});

    var language = [];
    $('#bulletinmodalfilters .filter-language input[type=radio]').each(function (){
        if ($(this).prop('checked')){
            language.push($(this).val());
        }
    });
    jsonObj.push({'language':language});

    var year = [];
    $('#bulletinmodalfilters .filter-year input[type=radio]').each(function (){
        if ($(this).prop('checked')){
            year.push($(this).val());
        }
    });
    jsonObj.push({'year':year});

    // Save it
    $('#userfilters').val(JSON.stringify(jsonObj));

    savedFiltersToCrumbs();
}

function savedFiltersToTemplate(){
    var jsonFilters = null;
    if ($('#userfilters').val() && $('#userfilters').val().length){
        jsonFilters = JSON.parse($('#userfilters').val());
    }

    $('#bulletinmodalfilters #filter-format-any').prop('checked', true);
    $('#bulletinmodalfilters #filter-language-any').prop('checked', true);
    $('#bulletinmodalfilters #filter-year-any').prop('checked', true);
    
    if (jsonFilters != null){
        $(jsonFilters).each(function(_index, _row){
            if (_row.format !== undefined && _row.format.length > 0){
                $('#bulletinmodalfilters .filter-format input[type=radio]').each(function (){
                    if (_row.format.indexOf($(this).val()) !== -1){
                        $(this).prop('checked', true)
                    }
                });
            }
            if (_row.language !== undefined && _row.language.length > 0){
                $('#bulletinmodalfilters .filter-language input[type=radio]').each(function (){
                    if (_row.language.indexOf($(this).val()) !== -1){
                        $(this).prop('checked', true)
                    }
                });
            }
            if (_row.year !== undefined && _row.year.length > 0){
                $('#bulletinmodalfilters .filter-year input[type=radio]').each(function (){
                    if (_row.year.indexOf($(this).val()) !== -1){
                        $(this).prop('checked', true)
                    }
                });
            }
        });
    }
}

function savedFiltersToCrumbs(){
    var jsonFilters = null;
    if ($('#userfilters').val() && $('#userfilters').val().length){
        jsonFilters = JSON.parse($('#userfilters').val());
    }
    
    $('#filtersApplied').html("");
    var filtersHTML = "";
    if (jsonFilters != null){
        $(jsonFilters).each(function(_index, _row){
            if (_row.format !== undefined && _row.format.length > 0){
                $(_row.format).each( function (i, r){
                    var _tmp = r;
                    if ((eval('typeof MSG_FORMAT_' + r)) !== "undefined"){
                        _tmp = eval('MSG_FORMAT_' + r);
                    }
                    if (r.length > 0){
                        filtersHTML += "<span class='data-filter-applied' data-filter-name='format' data-filter-value='"+r+"'>" + _tmp + " <i class='fa fa-remove'></i></span>";
                    }
                    
                });
            }

            if (_row.language !== undefined && _row.language.length > 0){
                $(_row.language).each( function (i, r){
                    var _tmp = r;
                    if ((eval('typeof MSG_LANGUAGE_' + r)) !== "undefined"){
                        _tmp = eval('MSG_LANGUAGE_' + r);
                    }
                    if (r.length > 0){
                        filtersHTML += "<span class='data-filter-applied' data-filter-name='language' data-filter-value='"+r+"'>" + _tmp + " <i class='fa fa-remove'></i></span>";
                    }
                });
            }

            if (_row.year !== undefined && _row.year.length > 0){
                $(_row.year).each( function (i, r){
                    if (r.length > 0){
                        filtersHTML += "<span class='data-filter-applied' data-filter-name='year' data-filter-value='"+r+"'>" + r + " <i class='fa fa-remove'></i></span>";
                    }
                });
            }
            
        });
    }
    $('#filtersApplied').html(filtersHTML);
    
    $('span.data-filter-applied').each( function(){
        $(this).on("click", function(e){
            e.preventDefault();
            removeFilter($(this).attr('data-filter-name'), $(this).attr('data-filter-value'));
            
            // Reload the content
            $('#bulletin').createBulletin();
        });
    });
}

function removeFilter(name, value){
    
    var jsonFilters = null;
    if ($('#userfilters').val().length){
        jsonFilters = JSON.parse($('#userfilters').val());
    }
    if (jsonFilters != null){
        var jsonObj = [];


        $(jsonFilters).each(function(index, row){
            var filter = [];
            
            if (Object.keys(row)[0] !== name){
                jsonObj.push(row);
                return true;
            }else{
                if (row[name] !== undefined && row[name].length > 0){
                    $(row[name]).each( function (i, r){
                        if (r !== value) {
                            filter.push(r);
                        }
                    });
                }
            }
            
            jsonObj.push({[name]:filter});
        });

        // Save it
        $('#userfilters').val(JSON.stringify(jsonObj));

        savedFiltersToCrumbs();
        savedFiltersToTemplate();
    }
}

$(function() {
    if ($('#bulletin').length){
        $('#bulletin').createBulletin();
    }
    
    $('#btn-bulletin-list').click(function (e){
        e.preventDefault();
        bulletinSwitchView('list');
        $(this).addClass('hidden');
        $('#btn-bulletin-grid').removeClass('hidden');
        // Save the last format used
        $('#userfilters').attr('data-defaultview', 'list');
    });
    $('#btn-bulletin-grid').click(function (e){
        e.preventDefault();
        bulletinSwitchView('grid');
        $(this).addClass('hidden');
        $('#btn-bulletin-list').removeClass('hidden');
        // Save the last format used
        $('#userfilters').attr('data-defaultview', 'grid');
    });
    $('#btn-filter-reset').click(function (e){
        e.preventDefault();
        $('#bulletinmodalfilters #filter-format-any').prop('checked', true);
        $('#bulletinmodalfilters #filter-language-any').prop('checked', true);
        $('#bulletinmodalfilters #filter-year-any').prop('checked', true);
    });
    $('#btn-filter-apply').click(function (e){
        e.preventDefault();
        saveApplyFilters();
        $('#bulletinmodalfilters').modal('toggle');
        var lastformatused = $('#userfilters').attr('data-defaultview');

        $('#bulletin').createBulletin();
    });
    
    $( "#otherlibraries" ).change(function() {
        if ($(this).val() != '') {
            var routetype = $('#route_type').val();
            if (routetype == 'CGI') {
                window.location.href = '/cgi-bin/koha/opac-bulletin.pl?id=' + $(this).val();
            } else {
                window.location.href = '/bulletins/opac-bulletin.pl?id=' + $(this).val();
            }
        }
    });
    
    $('#bulletinmodalfilters').on('show.bs.modal', function() {
        $(this).removeClass("hidden");
    });
    $('#bulletinmodalfilters').on('hide.bs.modal', function() {
        $(this).addClass("hidden");
    });
    savedFiltersToTemplate();
    savedFiltersToCrumbs();
});
