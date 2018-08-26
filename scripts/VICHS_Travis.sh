#!/bin/bash

# VICHS - Version Include Checksum Sort

for i in "$@"; do

    # Filtr to nazwa pliku, który chcemy zbudować
    FILTR=$(basename $i .txt)

    # Sciezka to miejsce, w którym znajduje się skrypt
    sciezka=$(dirname "$0")

    
    TEMPLATE=$sciezka/../templates/${FILTR}.template
    KONCOWY=$i
    TYMCZASOWY=$sciezka/../${FILTR}.temp
    
    # Jeżeli nie jest to plik PPB ani PPB_uBlock_AdGuard, to oznacza, że mamy do czynienia z modułem/modułami, a więc ścieżka zawsze będzie prowadzić do sekcji głównej listy, a includowanie supplementów zostawimy dla uBO i AG :-)
    if [ "${FILTR}" == 'PPB' ] || [ "${FILTR}" == 'PPB_uBlock_AdGuard' ]; then
        SEKCJE_KAT=$sciezka/../${FILTR}
    else
        SEKCJE_KAT=$sciezka/../PPB
    fi

    # Podmienianie zawartości pliku końcowego na zawartość template'u
    cp -R $TEMPLATE $KONCOWY
    
    # Usuwanie pustych linii z sekcji
    find ${SEKCJE_KAT} -type f -exec sed -i '/^$/d' {} \;
    
    # Sortowanie sekcji z pominięciem tych, które zawierają specjalne instrukcje
    find ${SEKCJE_KAT} -type f ! -iname ""*_specjalne_instrukcje.txt"" -exec sort -uV -o {} {} \;

    # Obliczanie ilości sekcji (wystąpień słowa @include w template'cie
    END=$(grep -o -i '@include' ${TEMPLATE} | wc -l)

    # Doklejanie sekcji w odpowiednie miejsca
    for (( n=1; n<=$END; n++ ))
    do
        SEKCJA=$(grep -oP -m 1 '@include \K.*' $KONCOWY)
        sed -e '0,/^@include/!b; /@include/{ r '${SEKCJE_KAT}/${SEKCJA}.txt'' -e 'd }' $KONCOWY > $TYMCZASOWY
        cp -R $TYMCZASOWY $KONCOWY
    done

    # Obliczanie ilości sekcji/list filtrów, które zostaną pobrane ze źródeł zewnętrznych
    END_URL=$(grep -o -i '@URLinclude' ${TEMPLATE} | wc -l)

    # Doklejanie zawartości zewnętrznych plików w odpowiednie miejsca
    for (( n=1; n<=$END_URL; n++ ))
    do
        ZEWNETRZNY=$(grep -oP -m 1 '@URLinclude \K.*' $KONCOWY)
        wget -O $SEKCJE_KAT/external.temp "${ZEWNETRZNY}"
        sed -i '/! Checksum/d' $SEKCJE_KAT/external.temp
        sed -i '/!#include /d' $SEKCJE_KAT/external.temp
        sed -i '/Adblock Plus 2.0/d' $SEKCJE_KAT/external.temp
        sed -i '/! Dołączenie listy/d' $SEKCJE_KAT/external.temp
        sed -i "s|! |!@|g" $SEKCJE_KAT/external.temp
        sed -e '0,/^@URLinclude/!b; /@URLinclude/{ r '$SEKCJE_KAT/external.temp'' -e 'd }' $KONCOWY > $TYMCZASOWY
        cp -R $TYMCZASOWY $KONCOWY
        rm -r $SEKCJE_KAT/external.temp
    done
    
    # Usuwanie tymczasowego pliku
    rm -r $TYMCZASOWY

    # Przejście do katalogu, w którym znajduje się lokalne repozytorium git
    cd $sciezka/..
    
    # Ustawianie nazwy kodowej (krótszej nazwy listy filtrów) do opisu commita w zależności od tego, co jest wpisane w polu „Codename:". Jeśli nie ma takiego pola, to codename=nazwa_pliku.
    if grep -q "! Codename" $i; then
        filtr=$(grep -oP -m 1 '! Codename: \K.*' $i);
    else
        filtr=$(basename $i);
    fi
    
    # Dodawanie zmienionych sekcji do repozytorium git
    git config --global user.email "PolishJarvis@int.pl"
    git config --global user.name "PolishJarvis"
    git add $SEKCJE_KAT/*
    git commit -m "Update sections of $filtr [ci skip]"
    
    # Ustawienie polskiej strefy czasowej
    export TZ=":Poland"

    # Aktualizacja daty i godziny w polu „Last modified"
    export LC_ALL=C
    modified=$(date +"%a, %d %b %Y, %H:%M UTC%:::z")
    sed -i "s|@modified|$modified|g" $i

    # Aktualizacja wersji
    wersja=$(date +"%Y%m%d%H%M")
    sed -i "s|@wersja|$wersja|g" $i

    # Aktualizacja pola „aktualizacja"
    export LC_ALL=pl_PL.UTF-8
    aktualizacja=$(date +"%a, %d %b %Y, %H:%M UTC%:::z")
    sed -i "s|@aktualizacja|$aktualizacja|g" $i
    
    # Aktualizacja sumy kontrolnej
    # Założenie: kodowanie UTF-8 i styl końca linii Unix
    # Usuwanie starej sumy kontrolnej i pustych linii
    grep -v '! Checksum: ' $i | grep -v '^$' > $i.chk
    # Pobieranie sumy kontrolnej... Binarny MD5 zakodowany w Base64
    suma_k=`cat $i.chk | openssl dgst -md5 -binary | openssl enc -base64 | cut -d "=" -f 1`
    # Zamiana atrapy sumy kontrolnej na prawdziwą
    sed -i "/! Checksum: /c\! Checksum: $suma_k" $i
    rm -r $i.chk
    
    # Dodawanie zmienionych plików do repozytorium git
    git add $i
    git commit -m "Update $filtr to version $wersja [ci skip]"
    git push https://PolishJarvis:${GH_TOKEN}@github.com/PolishFiltersTeam/PolishAnnoyanceFilters.git HEAD:master > /dev/null 2>&1
done
