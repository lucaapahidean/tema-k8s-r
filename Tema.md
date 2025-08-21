# Tema: Site web cu chat și IA peste Kubernetes

## Enunț
Obiectivul temei este de a crea un website ce conține o aplicație de chat și o aplicație de IA, implementate folosind mai multe deployment-uri gestionate de un cluster Kubernetes. Arhitectura aplicației va cuprinde mai multe elemente:

1.  **Content Management System (CMS)**
    * Tehnologie asignată: **Wordpress** cu **4 replici**.
    * Site-ul va fi expus pe portul 80.
    * Se va construi un site simplu (magazin, pizzerie, blog etc.).
    * CMS-ul va utiliza o bază de date proprie, la alegerea dumneavoastră (ex: MySQL).

2.  **Sistem de Chat**
    * Va fi integrat în pagina CMS-ului folosind un `iframe`.
    * **Backend**: Implementat cu protocolul WebSocket folosind **Python+Nginx**, cu **2 replici**. Serverul va fi expus pe portul 88.
    * **Frontend**: Implementat cu **React**, cu **1 replică**. Clientul va fi expus pe portul 90.
    * **Funcționalități**: Un formular de trimitere a mesajelor, afișarea istoricului mesajelor în ordine cronologică.
    * **Stocare Mesaje**: Se vor salva numele utilizatorului, mesajul (text, ASCII) și timestamp-ul.

3.  **Aplicație de Inteligență Artificială (IA)**
    * Va fi integrată în pagina CMS-ului folosind un `iframe`.
    * **Funcționalități**: O pagină web pentru upload-ul unui fișier ce va fi procesat de un serviciu de IA. Se va menține un istoric al cererilor și rezultatelor.
    * **Frontend**: Implementat cu **React**, cu **1 replică**.
    * **Stocare Fișiere**: Se va utiliza **Azure Blob Storage**.
    * **Stocare Metadate**: Informațiile despre fișiere (nume, adresă blob, timestamp, rezultat) vor fi stocate într-o **bază de date SQL hostată în Azure**.
    * **Serviciu IA**: Se va folosi serviciul **image description** de la Azure.

## Detalii de Implementare
* Imaginile custom create trebuie stocate într-un **registry privat** al clusterului Kubernetes.
* Se vor folosi Dockerfile-uri de tip **multi-stage** pentru a reduce dimensiunea imaginilor.
* Întreaga arhitectură trebuie pornită dintr-o singură comandă: `kubectl apply`.
* **Atenție**: După executarea comenzii `apply`, nicio altă configurare manuală nu este permisă, nici măcar la nivelul interfeței web a CMS-ului.

## Prezentare și Punctare
* În momentul prezentării, clusterul Kubernetes trebuie să fie pornit și gol (fără obiecte create).
* Se va rula comanda `apply`, iar apoi se va demonstra funcționalitatea corectă a tuturor componentelor.
* Punctajul va fi distribuit conform specificațiilor din fișa temei, incluzând o sesiune de întrebări practice la linia de comandă.