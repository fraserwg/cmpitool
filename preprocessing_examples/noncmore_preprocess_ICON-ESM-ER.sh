#!/usr/bin/bash

Help()
{
   # Display Help
	echo "###############################################################################"
	echo "# This is an example script preparing climate output without CMOR complient   #"
	echo "# output for the cmip-tool                                                    #"
	echo "# Author:     Jan Streffing 2022-01-18					                              #"
	echo "# adapted by: Christian Stepanek                                              #"
	echo "#             Fraser Goldsworth                                               #"
	echo "###############################################################################"
	echo "# Positional arguments:                                                       #"
	echo "#  1  directory containing raw model output                                   #"
	echo "#  2  cmpi input subdirectory                                                 #"
	echo "#  3  name of climate model                                                   #"
	echo "# Positional optional argument:                                               #"
	echo "#  4  boolean to delete tmp files                                             #"
	echo "#  5  integer specifying first model year to process                          #"
	echo "#  6  integer specifying last model year to process                           #"
    echo "#  7  string specifying path to and name of gridfile                          #"
    echo "#  8  string specifying directory path for processed data                     #"
    echo "#  9  string specifying fesom file name suffix                                #"
    echo "# 10  string specifying echam file name suffix                                #"
	echo "###############################################################################"
}

# Structure of the script:
# I have split each of the variables required by cmpitool up into a few different
# "types". These are:
# - ocean model level
# - ocean twoD 
# - ocean twoD (variance)
# - atmosphere model level
# - atmosphere twoD
# Unlike the sample CMPITool scripts, all the processing for each type of variable happens in one go.


# A smple folder showing the required inputs can be found here: (template)
# /work/ab0995/a270251/software/cmpitool/input
Help
ulimit -s 10000000
export PROCS=8
BATCH_SIZE=6

origdir="/work/bm1344/k203123/experiments/erc2002"
outdir="/work/mh0256/m301014/cmpitool/data/postprocessing/icon-esm-er"
model_name="ICON-ESM-ER"
deltmp=$4
export first_year=1991
export last_year=2021
gridfile=$7
export tmpdir="/work/mh0256/m301014/cmpitool/data/temp/icon-esm-er"
fesom_filename_suffix=${9:-}
echam_filename_suffix=${10:-}

module load cdo
module load parallel

if [ ! -d ${outdir} ]
then
  mkdir -p ${outdir}
fi
if [ ! -d ${tmpdir} ]
then
  mkdir -p ${tmpdir}
fi
cd $outdir



printf "##################################\n"
printf "# Construct the data paths       #\n"
printf "##################################\n"
ML_FILES=()
TWOD_FILES=()
OCE_VAR_FILES=()
ATM_TWOD_FILES=()
ATM_ML_FILES=()
for YEAR in $(seq ${first_year} ${last_year});
do
    ML_FILES+=( ${origdir}/run_????????T000000-????????T235900/*_oce_ml_1mth_mean_${YEAR}????T000000Z.nc )
    TWOD_FILES+=( ${origdir}/run_????????T000000-????????T235900/*_oce_2d_1mth_mean_${YEAR}????T000000Z.nc )
    OCE_VAR_FILES+=( ${origdir}/run_????????T000000-????????T235900/*_oce_2d_1mth_sqr_${YEAR}????T000000Z.nc )
    ATM_TWOD_FILES+=( ${origdir}/run_????????T000000-????????T235900/*_atm_2d_1mth_mean_${YEAR}????T000000Z.nc )
    ATM_ML_FILES+=( ${origdir}/run_????????T000000-????????T235900/*_atm_ml_1mth_mean_${YEAR}????T000000Z.nc )
done

printf "##################################\n"
printf "# Operate on ML data             #\n"
printf "##################################\n"
printf "construct interpolation weights\n"
export ML_WGHTS="${tmpdir}/ML_weights.nc"
cdo -P ${PROCS} -gencon,r180x91 -intlevel,10,100,1000,4000 -setctomiss,0 -selvar,to "${ML_FILES[0]}" "${ML_WGHTS}"


printf "Select var, interpolate levels and remap\n"
ml_processing() {
    file=$1
    filename=$(basename "${file}")
    echo "Operating on ${filename}"
    cdo -P ${PROCS} -remap,r180x91,"${ML_WGHTS}" -intlevel,10,100,1000,4000 -setctomiss,0 -chname,to,thetao -selvar,to -selyear,"${first_year}"/"${last_year}" "${file}" "${tmpdir}/thetao.gr2.${filename}"
    cdo -P ${PROCS} -remap,r180x91,"${ML_WGHTS}" -intlevel,10,100,1000,4000 -setctomiss,0 -selvar,so -selyear,"${first_year}"/"${last_year}" "${file}" "${tmpdir}/so.gr2.${filename}"
}
export -f ml_processing
parallel --jobs $BATCH_SIZE "ml_processing {}" ::: "${ML_FILES[@]}"

printf " Mergetime, splitseason, rename\n"
for var in thetao so;
do
    cdo -P ${PROCS} -mergetime "${tmpdir}/${var}.gr2.*.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12.nc"
    cdo -P ${PROCS} -splitlevel "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_"
    mv "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_000010.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_10m.nc"
    mv "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_000100.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_100m.nc"
    mv "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_001000.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_1000m.nc"
    mv "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_004000.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_4000m.nc"

    for level in 10 100 1000 4000;
    do
        cdo -P ${PROCS} -splitseas -yseasmean "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_${level}m.nc" "${outdir}/${var}_${model_name}_${first_year}01-${last_year}12_${level}m_"
    done
done





printf "##################################\n"
printf "# Operate on Ocean TWOD data     #\n"
printf "##################################\n"
printf "construct interpolation weights\n"
export TWOD_WGHTS="${tmpdir}/TWOD_weights.nc"
cdo -P ${PROCS} -gencon,r180x91 -setctomiss,0 -selvar,to "${TWOD_FILES[0]}" "${TWOD_WGHTS}"


printf "Select var, interpolate levels and remap\n"
twod_processing() {
    file=$1
    filename=$(basename "${file}")
    echo "Operating on ${filename}"
    cdo -P ${PROCS} -remap,r180x91,"${TWOD_WGHTS}" -chname,conc,siconc -selvar,conc -selyear,"${first_year}"/"${last_year}" "${file}" "${tmpdir}/siconc.gr2.${filename}"
    cdo -P ${PROCS} -remap,r180x91,"${TWOD_WGHTS}" -setctomiss,0 -chname,mlotst10,mlotst -selvar,mlotst10 -selyear,"${first_year}"/"${last_year}" "${file}" "${tmpdir}/mlotst.gr2.${filename}"
}
export -f twod_processing
parallel --jobs $BATCH_SIZE "twod_processing {}" ::: "${TWOD_FILES[@]}"

printf " Mergetime, splitseason, rename\n"
for var in siconc mlotst;
do
    cdo -P ${PROCS} -splitseas -yseasmean -mergetime "${tmpdir}/${var}.gr2.*.nc" "${tmpdir}/${var}_${model_name}_${first_year}01-${last_year}12_surface_"
done



# # Need

# # Parallel environment options
# export PROCS=12  # Number of processes used by cdo.
# # The script seems to use 256GB of memory with procs=12 and batch_size=1 so
# # here we use array jobs to add further parallelism. (That's embarassing.)
# export BATCH_SIZE=16  # Number of parallel processes to run concurrently. Set to 1 for debugging.

# # Data processing options
# # export YYYY=1991
# export YYYY=${SLURM_ARRAY_TASK_ID}

# module load cdo
# module load parallel

# export ERC_PATH="/work/bm1344/k203123/experiments/erc2002/run_${YYYY}????T000000-${YYYY}????T235900"
# export SCRATCH="/scratch/m/m301014/temp"
# export LSM="/work/bm1344/DKRZ/ICON/erc1011/postprocessing/interpolation/r2b9O_lsm.nc"
# export LSM_1000="/scratch/m/m301014/temp/grid_weights/r2b9_lsm_1000.nc"
# mkdir -p "${SCRATCH}/grid_weights"
# mkdir -p "${SCRATCH}/remapped"


# export ICON_GRID="/pool/data/ICON/grids/public/mpim/0016/icon_grid_0016_R02B09_O.nc"
# export P1M_2D="erc2002_oce_2d_1mth_mean_????????T000000Z.nc"
# export P1D_2D="erc2002_oce_2d_1d_mean_????????T000000Z.nc"
# export P1M_ML="erc2002_oce_ml_1mth_mean_????????T000000Z.nc"
# export P1M_EDDY="erc2002_oce_eddy_1mth_mean_????????T000000Z.nc"
# export P1M_ATM_2D="erc2002_atm_2d_1mth_mean_????????T000000Z.nc"

# # Generate the conservative and nearest neighbour weights
# # We generate one weight file for each parallel job to prevent multiple
# # processesors trying to simulataneously access the same file.
# export INPUT_FILES=(${ERC_PATH}/${P1M_2D})
# export CONSERVATIVE_WGHTS="${SCRATCH}/grid_weights/conservative_${YYYY}.nc"
# export FABIAN_WGHTS="/work/bm1344/DKRZ/ICON/erc1011/postprocessing/interpolation/r2b9O_IFS25invertlat_yconremapweights_lsm.nc"
# export FULL_WEIGHTS="/work/bm1344/DKRZ/ICON/erc1011/postprocessing/interpolation/r2b9O_IFS25invertlat_yconremapweights_lsm_3d_full.nc"
# export CONSERVATIVE_WGHTS_1000="${SCRATCH}/grid_weights/conservative_${YYYY}_1000m.nc"

# echo "Conservative weights_1000"
# # cdo -P "${PROCS}" -sellevel,997.9 "${FULL_WEIGHTS}" "${CONSERVATIVE_WGHTS_1000}"

# echo "Copying"
# cp "${FABIAN_WGHTS}" "${CONSERVATIVE_WGHTS}"

# # export NEAREST_WGHTS="${SCRATCH}/grid_weights/nearestneighbour_${YYYY}.nc"
# generate_weights() {
#     input_file=$1
#     slot=$2
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"
#     cdo griddes "/work/bm1344/wp6/d6.1/model-output/icon-esm-er/scripts/grid025.nc" > "${griddes_file}"
#     echo cdo -P 32 gencon,"${griddes_file}" -setgrid,"${ICON_GRID}" "${input_file}" "${CONSERVATIVE_WGHTS}.${slot}"
#     cdo -P 32 gencon,"${griddes_file}" -setgrid,"${ICON_GRID}" "${input_file}" "${CONSERVATIVE_WGHTS}.${slot}"
#     # cp "${CONSERVATIVE_WGHTS}" "${CONSERVATIVE_WGHTS}.${slot}"
#     # cp "${CONSERVATIVE_WGHTS_1000}" "${CONSERVATIVE_WGHTS_1000}.${slot}"
    
#     # cdo gennn,global025 "${INPUT_FILE}" "${NEAREST_WGHTS}.${slot}"
# }
# export -f generate_weights

# echo "Generating weights"
# export P1M_ML_FILES=(${ERC_PATH}/${P1M_ML})

# # Generate the 1000 m velocity weigths
# griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des"
# cdo griddes "/work/bm1344/wp6/d6.1/model-output/icon-esm-er/scripts/grid025.nc" > "${griddes_file}"
# cdo -P 32 gencon,"${griddes_file}" -setgrid,"${ICON_GRID}" -div -sellevel,997.9 -selvar,u "${P1M_ML_FILES[0]}" "${LSM_1000}" "${CONSERVATIVE_WGHTS_1000}"

# # parallel --jobs $BATCH_SIZE "generate_weights {} {%}" ::: "${P1M_ML_FILES[@]:0:${BATCH_SIZE}}"

# # Operate on P1D_2D
# operate_P1D_2D() {
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     ssh_out_name="icon-esm-er.erc2002.control.gr.ssh.P1D.${yyyymmdd}.nc"
    
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"
#     echo "Saving ouptut to ${ssh_out_name}"
#     echo cdo -P ${PROCS} -remap,"${griddes_file}","${CONSERVATIVE_WGHTS}.${slot}" -div -selvar,ssh "${input_file}" "${LSM}" "${out_folder}/${ssh_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}","${CONSERVATIVE_WGHTS}.${slot}" -div -selvar,ssh "${input_file}" "${LSM}" "${out_folder}/${ssh_out_name}"
#     # cdo -P ${PROCS} -remap,"${griddes_file}","${CONSERVATIVE_WGHTS}.${slot}" -div -selvar,ssh "${input_file}" "${LSM}" "${out_folder}/${ssh_out_name}"   
# }
# export -f operate_P1D_2D

# export P1D_2D_FILES=(${ERC_PATH}/${P1D_2D})
# # parallel --jobs $BATCH_SIZE "operate_P1D_2D {} {%}" ::: "${P1D_2D_FILES[@]}"

# # Operate on P1M_2D
# operate_P1M_2D() {
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"
    
#     # # Do SST:
#     # export to_out_name="icon-esm-er.erc2002.control.gr.to.P1M.${yyyymmdd}.nc"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,to "${input_file}" "${LSM}" "${out_folder}/${to_out_name}"

#     # # Do SSS
#     # export so_out_name="icon-esm-er.erc2002.control.gr.so.P1M.${yyyymmdd}.nc"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,so "${input_file}" "${LSM}" "${out_folder}/${so_out_name}"

#     # # Do MLD
#     # export mld_out_name="icon-esm-er.erc2002.control.gr.mlotst10.P1M.${yyyymmdd}.nc"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,mlotst10 "${input_file}" "${LSM}" "${out_folder}/${mld_out_name}"

#     # # Do CONC
#     # export conc_out_name="icon-esm-er.erc2002.control.gr.conc.P1M.${yyyymmdd}.nc"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,conc "${input_file}" "${LSM}" "${out_folder}/${conc_out_name}"

#     # Do SITHICKNESS
#     export hi_out_name="icon-esm-er.erc2002.control.gr.hi.P1M.${yyyymmdd}.nc"
#     export hs_out_name="icon-esm-er.erc2002.control.gr.hs.P1M.${yyyymmdd}.nc"

#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,hi "${input_file}" "${LSM}" "${out_folder}/${hi_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -selvar,hs "${input_file}" "${LSM}" "${out_folder}/${hs_out_name}"

# }
# export -f operate_P1M_2D

# export P1M_2D_FILES=(${ERC_PATH}/${P1M_2D})
# # parallel --jobs $BATCH_SIZE "operate_P1M_2D {} {%}" ::: "${P1M_2D_FILES[@]}"

# OPERATE_P1M_ATM_2D(){
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"

#     export pr_out_name="icon-esm-er.erc2002.control.gr.pr.P1M.${yyyymmdd}.nc"
#     cdo -P ${PROCS} -remapcon,"${griddes_file}" -selvar,pr "${input_file}" "${out_folder}/${pr_out_name}"
#     echo "Saved to: ${out_folder}/${pr_out_name}"
# }
# export -f OPERATE_P1M_ATM_2D

# export P1M_ATM_2D_FILES=(${ERC_PATH}/${P1M_ATM_2D})
# parallel --jobs $BATCH_SIZE "OPERATE_P1M_ATM_2D {} {%}" ::: "${P1M_ATM_2D_FILES[@]}"

# operate_P1M_ML() {
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"

#     # Do U0, V0
#     echo "Remapping u0 and v0"
#     echo "Skip"
#     # export u0_out_name="icon-esm-er.erc2002.control.gr.u0.P1M.${yyyymmdd}.nc"
#     # export v0_out_name="icon-esm-er.erc2002.control.gr.v0.P1M.${yyyymmdd}.nc"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -sellevel,1 -selvar,u "${input_file}" "${LSM}" "${out_folder}/${u0_out_name}"
#     # cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -sellevel,1 -selvar,v "${input_file}" "${LSM}" "${out_folder}/${v0_out_name}" 

#     # Do U1000, V1000
#     echo "Remapping u1000 and v1000"
#     export u1000_out_name="icon-esm-er.erc2002.control.gr.u1000.P1M.${yyyymmdd}.nc"
#     export v1000_out_name="icon-esm-er.erc2002.control.gr.v1000.P1M.${yyyymmdd}.nc"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS_1000}.${slot} -div -sellevel,997.9 -selvar,u "${input_file}" "${LSM_1000}" "${out_folder}/${u1000_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS_1000}.${slot} -div -sellevel,997.9 -selvar,v "${input_file}" "${LSM_1000}" "${out_folder}/${v1000_out_name}"
# }
# export -f operate_P1M_ML

# surfavg_P1M_ML() {
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"

#     # Doing surface 15m avarge
#     echo "Doing surface 15m average"
#     export u15_out_name="icon-esm-er.erc2002.control.gr.u15mn.P1M.${yyyymmdd}.nc"
#     export v15_out_name="icon-esm-er.erc2002.control.gr.v15mn.P1M.${yyyymmdd}.nc"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -vertavg -select,levrange=0,15 -genlevelbounds,zbot=5950.8,ztop=0 -selvar,u "${input_file}" "${out_folder}/${u15_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -vertavg -select,levrange=0,15 -genlevelbounds,zbot=5950.8,ztop=0 -selvar,v "${input_file}" "${out_folder}/${v15_out_name}"

#     # Doing surface 30m avarge
#     echo "Doing surface 30m average"
#     export u30_out_name="icon-esm-er.erc2002.control.gr.u30mn.P1M.${yyyymmdd}.nc"
#     export v30_out_name="icon-esm-er.erc2002.control.gr.v30mn.P1M.${yyyymmdd}.nc"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -vertavg -select,levrange=0,30 -genlevelbounds,zbot=5950.8,ztop=0 -selvar,u "${input_file}" "${out_folder}/${u30_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -vertavg -select,levrange=0,30 -genlevelbounds,zbot=5950.8,ztop=0 -selvar,v "${input_file}" "${out_folder}/${v30_out_name}"
# }
# export -f surfavg_P1M_ML

# # echo "Operating on P1M_ML_FILES"
# export P1M_ML_FILES=(${ERC_PATH}/${P1M_ML})
# # parallel --jobs $BATCH_SIZE "operate_P1M_ML {} {%}" ::: "${P1M_ML_FILES[@]}"
# # parallel --jobs $BATCH_SIZE "surfavg_P1M_ML {} {%}" ::: "${P1M_ML_FILES[@]}"


# operate_P1M_EDDY() {
#     input_file=$1
#     slot=$2
#     echo "Operating on ${input_file}"
    
#     # Get the run_YYYYMMDDT000000-YYYYMMDDT235900 folder
#     dirpath=$(dirname ${input_file})
#     dirname=$(basename ${dirpath})
#     out_folder="${SCRATCH}/remapped/${dirname}"
#     mkdir -p "${out_folder}"

#     yyyymmdd="${input_file: -19:-11}"
#     griddes_file="${SCRATCH}/grid_weights/grid025_${YYYY}.des.${slot}"

#     # Do Usq0, Vsq0
#     export usq0_out_name="icon-esm-er.erc2002.control.gr.usq0.P1M.${yyyymmdd}.nc"
#     export vsq0_out_name="icon-esm-er.erc2002.control.gr.vsq0.P1M.${yyyymmdd}.nc"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -sellevel,1 -selvar,uu "${input_file}" "${LSM}" "${out_folder}/${usq0_out_name}"
#     cdo -P ${PROCS} -remap,"${griddes_file}",${CONSERVATIVE_WGHTS}.${slot} -div -sellevel,1 -selvar,vv "${input_file}" "${LSM}" "${out_folder}/${vsq0_out_name}"
# }
# export -f operate_P1M_EDDY

# export P1M_EDDY_FILES=(${ERC_PATH}/${P1M_EDDY})
# # parallel --jobs $BATCH_SIZE "operate_P1M_EDDY {} {%}" ::: "${P1M_EDDY_FILES[@]}"