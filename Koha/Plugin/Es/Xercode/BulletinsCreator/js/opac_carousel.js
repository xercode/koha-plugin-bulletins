$(function() {
    /* Creamos un contenedor para el HTML de nuestra variable y hacemos que la variable sea el primer hijo de ese contenedor*/
    let contenedor = document.createElement("div");
    contenedor.innerHTML = code;
    code = contenedor.firstChild;

    var body = document.getElementById("opac-main");
    if (body) {
        var maincontent = document.querySelector('.maincontent');
        if(maincontent){
            maincontent.appendChild(code);
            KOHA.LocalCover.GetCoverFromBibnumber(false);
        }
    }
    
});