base="/pool/data/CMIP6/data/CMIP/SNU/SAM0-UNICON/historical/r1i1p1f1/"
model="SNU"
#vararray=("siconc" "tas" "clt" "pr" "rlut" "uas" "vas")
vararray=("ua" "zg")
mode="yearly" #onefile, yearly, decadal, five, four

for var in ${vararray[*]}; do
    if [[ "$var" = "siconc" ]]; then
        group="SImon"
        g="gn"
        version="v20190323"
    else
        group="Amon"
        g="gn"
        version="v20190323"
    fi
    if [[ "$mode" = "yearly" ]]; then
        ln -s $base/$group/$var/$g/$version/*_198* .
        ln -s $base/$group/$var/$g/$version/*_199* .
        ln -s $base/$group/$var/$g/$version/*_20* .
        rm -rf $var
        cdo mergetime ${var}_${group}_* $var &
    fi
    if [[ "$mode" = "onefile" ]]; then
        ln -s $base/$group/$var/$g/$version/*1850* $var
    fi
    if [[ "$mode" = "five" ]]; then
        ln -s $base/$group/$var/$g/$version/*1970* .
        ln -s $base/$group/$var/$g/$version/*20* .
        rm -rf $var
        cdo mergetime ${var}_${group}_* $var &
    fi
    if [[ "$mode" = "four" ]]; then
        ln -s $base/$group/$var/$g/$version/*1950* .
        ln -s $base/$group/$var/$g/$version/*20* .
        rm -rf $var
        cdo mergetime ${var}_${group}_* $var &
    fi
done
wait

if [[ "$mode" = "onefile" ]]; then
    steps="1680/1979"
elif [[ "$mode" = "five" ]]; then
    steps="240/539"
elif [[ "$mode" = "four" ]]; then
    steps="480/779"
else
    steps="120/419"
fi
for var in ${vararray[*]}; do
    if [[ "$var" = "zg" ]]; then
        cdo -remapbil,r180x91 -sellevel,50000 -seltimestep,$steps $var ${var}_${model}_198912-201411.nc &
    elif [[ "$var" = "ua" ]]; then
        cdo -remapbil,r180x91 -sellevel,30000 -seltimestep,$steps $var ${var}_${model}_198912-201411.nc &
    else
        cdo -remapbil,r180x91 -seltimestep,$steps $var ${var}_${model}_198912-201411.nc &
    fi
done
wait

for var in ${vararray[*]}; do
        cdo splitseas -yseasmean ${var}_${model}_198912-201411.nc ../../cmip6/${var}_${model}_198912-201411_
done