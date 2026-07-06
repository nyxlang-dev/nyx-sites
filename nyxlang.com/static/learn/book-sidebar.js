// book-sidebar.js — Injects sidebar TOC into all Nyx Book pages
(function() {
    var lang = document.documentElement.lang === 'es' ? 'es' : 'en';
    var base = lang === 'es' ? '/es/learn/' : '/learn/';
    var otherBase = lang === 'es' ? '/learn/' : '/es/learn/';
    var otherLabel = lang === 'es' ? 'EN' : 'ES';
    var thisLabel = lang === 'es' ? 'ES' : 'EN';

    var chapters = lang === 'es' ? [
        ['Parte 1: Aprender', null],
        ['1. Que es programar?', '01.html'],
        ['2. Variables y tipos', '02.html'],
        ['3. Operaciones', '03.html'],
        ['4. Control de flujo', '04.html'],
        ['5. Funciones', '05.html'],
        ['6. Arrays', '06.html'],
        ['7. Strings', '07.html'],
        ['8. Maps', '08.html'],
        ['9. Structs', '09.html'],
        ['10. Tu primer proyecto', '10.html'],
        ['Parte 2: Construir', null],
        ['11. Imports y modulos', '11.html'],
        ['12. Archivos', '12.html'],
        ['13. Closures', '13.html'],
        ['14. Enums y matching', '14.html'],
        ['15. Traits e impl', '15.html'],
        ['16. Generics', '16.html'],
        ['17. TCP servers', '17.html'],
        ['18. Concurrencia', '18.html'],
        ['19. Proyecto: web server', '19.html'],
        ['Parte 3: Dominar', null],
        ['20. LLVM y rendimiento', '20.html'],
        ['21. FFI — Codigo C', '21.html'],
        ['22. Unsafe y punteros', '22.html'],
        ['23. Async y event loop', '23.html'],
        ['24. Sistemas', '24.html'],
        ['25. Caso: nyx-kv', '25.html'],
        ['Parte 4: Produccion', null],
        ['26. Package manager', '26.html'],
        ['27. APIs con nyx-serve', '27.html'],
        ['28. Pub/Sub', '28.html'],
        ['29. nyx-queue', '29.html'],
        ['30. HTTP/2', '30.html'],
        ['31. nyx-db', '31.html'],
        ['Apendices', null],
        ['A: Sintaxis', 'apendice-a.html'],
        ['B: Stdlib', 'apendice-b.html'],
        ['C: Errores', 'apendice-c.html'],
        ['D: Glosario', 'apendice-d.html'],
        ['E: Colores', 'apendice-e.html']
    ] : [
        ['Part 1: Learn', null],
        ['1. What is programming?', '01.html'],
        ['2. Variables and types', '02.html'],
        ['3. Operations', '03.html'],
        ['4. Control flow', '04.html'],
        ['5. Functions', '05.html'],
        ['6. Arrays', '06.html'],
        ['7. Strings', '07.html'],
        ['8. Maps', '08.html'],
        ['9. Structs', '09.html'],
        ['10. Your first project', '10.html'],
        ['Part 2: Build', null],
        ['11. Imports and modules', '11.html'],
        ['12. Files', '12.html'],
        ['13. Closures', '13.html'],
        ['14. Enums and matching', '14.html'],
        ['15. Traits and impl', '15.html'],
        ['16. Generics', '16.html'],
        ['17. TCP servers', '17.html'],
        ['18. Concurrency', '18.html'],
        ['19. Project: web server', '19.html'],
        ['Part 3: Master', null],
        ['20. LLVM & performance', '20.html'],
        ['21. FFI — Calling C', '21.html'],
        ['22. Unsafe & pointers', '22.html'],
        ['23. Async & event loop', '23.html'],
        ['24. Systems', '24.html'],
        ['25. Case: nyx-kv', '25.html'],
        ['Part 4: Production', null],
        ['26. Package manager', '26.html'],
        ['27. APIs with nyx-serve', '27.html'],
        ['28. Pub/Sub', '28.html'],
        ['29. nyx-queue', '29.html'],
        ['30. HTTP/2', '30.html'],
        ['31. nyx-db', '31.html'],
        ['Appendices', null],
        ['A: Syntax reference', 'appendix-a.html'],
        ['B: Stdlib modules', 'appendix-b.html'],
        ['C: Error messages', 'appendix-c.html'],
        ['D: Glossary', 'appendix-d.html'],
        ['E: Syntax colors', 'appendix-e.html']
    ];

    var currentPage = location.pathname.split('/').pop() || 'index.html';

    var html = '<div class="sb-home"><a href="' + base + '">The Nyx Book</a> <span>v0.12</span></div>';
    html += '<div class="sb-lang"><a href="' + base + (currentPage === 'index.html' ? '' : currentPage) + '"' + (lang !== 'es' ? ' class="active"' : '') + '>' + (lang === 'es' ? otherLabel : thisLabel) + '</a> / ';
    html += '<a href="' + otherBase + (currentPage === 'index.html' ? '' : currentPage) + '"' + (lang === 'es' ? '' : '') + '>' + otherLabel + '</a></div>';

    for (var i = 0; i < chapters.length; i++) {
        var name = chapters[i][0];
        var file = chapters[i][1];
        if (!file) {
            html += '<div class="sb-section">' + name + '</div>';
        } else {
            var isActive = (currentPage === file) ? ' class="active"' : '';
            html += '<a href="' + base + file + '"' + isActive + '>' + name + '</a>';
        }
    }

    var aside = document.createElement('aside');
    aside.className = 'book-sidebar';
    aside.innerHTML = html;

    var content = document.querySelector('.book-content');
    if (content) {
        content.parentNode.insertBefore(aside, content);
        document.body.classList.add('has-sidebar');
    }
})();
