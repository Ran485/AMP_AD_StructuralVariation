#!/bin/bash

#################################################################################

# Copyright (c) 2019 Ricardo Vialle and Raj Laboratory
# Contact: Ricardo Vialle <ricardovialle@gmail.com>

## SV Pipeline - 02_Delly.sh
## Usage: ./collect_02_Delly.sh myConfigFile.config

## This script must be ran after all jobs from run_02_Delly.sh are finished.
## A folder Results will be created inside the folder 02_SVtools/Delly.

#################################################################################

display_usage() {
        echo "Script must run with the configuration file."
        echo -e "\nUsage:\n $0 myConfigFile.config \n"
        }

# if less than one argument supplied, display usage
if [[ $# -eq 0 ]] ; then
    display_usage
    exit 1
fi
# check whether user had supplied -h or --help . If yes display usage
if [[ ( $# == "--help") ||  $# == "-h" ]] ; then
    display_usage
    exit 0
fi
# load configFile
source $1
if ! [ -n "$bamFileList" ]; then
    echo "Something is wrong. bamFileList var is unset. Please check if the config file is OK.";
    exit 1
else
    echo "Loading config file seems OK. bamFileList='$bamFileList'.";
    lastline=$(tail -n1 $1)
    if [ "$lastline" = "#### End of file ####" ]; then
        echo "Last line seems OK.";
    else
        echo "Last line must be '#### End of file ####'. Please check if the config file is OK.";
        exit 1
    fi
fi

# =============================================================================
#                           Set folders and modules
# =============================================================================
# DELLY
# BND, DEL, DUP, INS, INV
# Filters:: 
# 01: Keep only calls from chr 1-22+X+Y
# 02: Removing SVs smaller than 50 bp
# 03: Keep only PASS calls
##

## Run folder
mkdir -p ${outputFolderPath} || exit 1
prevResultsDir=${outputFolderPath}"/02_SVtools/Delly"
runDir=${prevResultsDir}"/Results"
mkdir -p ${runDir} || exit 1
mkdir -p ${runDir}/svCalls || exit 1
mkdir -p ${runDir}/svFiltered || exit 1
mkdir -p ${runDir}/svBenchmark || exit 1
mkdir -p ${runDir}/SURVIVOR || exit 1

touch ${outputFolderPath}/svCalls.blacklist

## Loading modules
module purge
module load vcftools

# =============================================================================
#                           Collect results
# =============================================================================

## First check if all samples were processed and resulting files exist
echo "List with bam files: $bamFileList"
total_num_samples=$(cat $bamFileList | wc -l)
echo "Number of samples in the list: $total_num_samples"
DELCOUNTER=0
INSCOUNTER=0
DUPCOUNTER=0
INVCOUNTER=0
BNDCOUNTER=0
while [ 1 ]
do

    read bamFile || break
    fileName=$(basename "$bamFile")
    filename=$(basename -- "$bamFile")
    extension="${filename##*.}"
    filename="${filename%.*}"
    id=`echo $fileName | cut -d '.' -f 1`
    FLAG=0

    if [ ! -s "${prevResultsDir}/data/${id}.DEL.bcf" ]; then
       DELCOUNTER=$[$DELCOUNTER +1]
       FLAG=1
    fi
    if [ ! -s "${prevResultsDir}/data/${id}.INS.bcf" ]; then
       INSCOUNTER=$[$INSCOUNTER +1]
       FLAG=1
    fi
    if [ ! -s "${prevResultsDir}/data/${id}.DUP.bcf" ]; then
       DUPCOUNTER=$[$DUPCOUNTER +1]
       FLAG=1
    fi
    if [ ! -s "${prevResultsDir}/data/${id}.INV.bcf" ]; then
       INVCOUNTER=$[$INVCOUNTER +1]
       FLAG=1
    fi
    if [ ! -s "${prevResultsDir}/data/${id}.BND.bcf" ]; then
       BNDCOUNTER=$[$BNDCOUNTER +1]
       FLAG=1
    fi

    if [ $FLAG -eq 1 ]; then
       print "${id}\tDELLY_failed" >> ${outputFolderPath}/svCalls.blacklist
    fi

done < $bamFileList

echo "Number of failed samples (DEL calls): $DELCOUNTER"
echo "Number of failed samples (INS calls): $INSCOUNTER" 
echo "Number of failed samples (DUP calls): $DUPCOUNTER"
echo "Number of failed samples (INV calls): $INVCOUNTER"
echo "Number of failed samples (BND calls): $BNDCOUNTER"
totalFails=$((DELCOUNTER + INSCOUNTER + DUPCOUNTER + INVCOUNTER + BNDCOUNTER))
if [ $totalFails -gt 0 ]; then
    echo "Some samples had failed. Please fix first"
    exit 1
fi

## Loop over each sample
while [ 1 ]
do

    read bamFile || break
    fileName=$(basename "$bamFile")
    filename=$(basename -- "$bamFile")
    extension="${filename##*.}"
    filename="${filename%.*}"
    id=`echo $fileName | cut -d '.' -f 1`
    echo "|-- $bamFile ---- $id --|"

    # Convert bcf to vcf
    bcftools view ${prevResultsDir}/data/${id}.DEL.bcf > ${runDir}/svCalls/${id}.vcf
    bcftools view ${prevResultsDir}/data/${id}.DUP.bcf | grep -v '^#' >> ${runDir}/svCalls/${id}.vcf
    bcftools view ${prevResultsDir}/data/${id}.INS.bcf | grep -v '^#' >> ${runDir}/svCalls/${id}.vcf
    bcftools view ${prevResultsDir}/data/${id}.INV.bcf | grep -v '^#' >> ${runDir}/svCalls/${id}.vcf
    bcftools view ${prevResultsDir}/data/${id}.BND.bcf | grep -v '^#' >> ${runDir}/svCalls/${id}.vcf

    # Sort vcf
    vcf-sort -c ${runDir}/svCalls/${id}.vcf > ${runDir}/svCalls/${id}.sorted.vcf
    mv ${runDir}/svCalls/${id}.sorted.vcf ${runDir}/svCalls/${id}.vcf

    # Compress and index vcf
    bgzip -c ${runDir}/svCalls/${id}.vcf > ${runDir}/svCalls/${id}.vcf.gz
    tabix -p vcf ${runDir}/svCalls/${id}.vcf.gz

    ## Clean and organize VCF
    # Filter 01: keep only calls from chr 1-22+X+Y
    bcftools view ${runDir}/svCalls/${id}.vcf.gz --regions 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,X,Y > ${runDir}/svFiltered/${id}.vcf.01

    # Filter 02: Removing SVs greater smaller than 50 bp and greater than 10 Mb.
    SURVIVOR filter ${runDir}/svFiltered/${id}.vcf.01 NA 50 10000000 0 -1 ${runDir}/svFiltered/${id}.vcf.02
    # Warning: Max size threshold set, TRA wont be reported as their size cannot be assesst.

    # Filter 03: Keep only PASS calls
    awk -F '\t' '{if($0 ~ /\#/) print; else if($7 == "PASS") print}' ${runDir}/svFiltered/${id}.vcf.02 > ${runDir}/svFiltered/${id}.vcf.03

    # Rename sample id
    ${svpipeline_r_lib}/rename_SampleNamesInVCF.R ${runDir}/svFiltered/${id}.vcf.03 DELLY_${id} ${runDir}/svFiltered/${id}.vcf.04

    # Rename REF and ALF fields
    ${svpipeline_r_lib}/rename_REFandALT.R ${runDir}/svFiltered/${id}.vcf.04 ${runDir}/svFiltered/${id}.vcf.05.gz
    gunzip ${runDir}/svFiltered/${id}.vcf.05.gz # decompress

    # Copy/Rename last step to .filt
    cp ${runDir}/svFiltered/${id}.vcf.05 ${runDir}/svFiltered/${id}.vcf.filt

    # Extract Genotypes for each SV
    bgzip -c ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.gz
    tabix -p vcf ${runDir}/svFiltered/${id}.vcf.filt.gz
    bcftools query -f '%CHROM %POS %INFO/SVTYPE [%GT]\n' ${runDir}/svFiltered/${id}.vcf.filt.gz > ${runDir}/svFiltered/${id}.vcf.filt.genotypes
        
    # For Truvari compatibility - If your vcf has DUP calls that generally indicate insertions of tandem duplications (e.g., manta), then convert SVTYPE=DUP to SVTYPE=INS
    sed 's/SVTYPE=DUP/SVTYPE=INS/' ${runDir}/svFiltered/${id}.vcf.filt | grep -E '^#|SVTYPE=INS' > ${runDir}/svFiltered/${id}.vcf.filt.DUPtoINS

    # Splitting VCF into BND, DEL, DUP, INS, INV
    grep -E '^#|SVTYPE=DEL' ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.DEL

    grep -E '^#|SVTYPE=DUP' ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.DUP

    grep -E '^#|SVTYPE=INS' ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.INS

    grep -E '^#|SVTYPE=INV' ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.INV

    grep -E '^#|SVTYPE=BND' ${runDir}/svFiltered/${id}.vcf.filt > ${runDir}/svFiltered/${id}.vcf.filt.BND

    # Delly call TRA as BND. Renaming BND to TRA
    sed 's/SVTYPE=BND/SVTYPE=TRA/' ${runDir}/svFiltered/${id}.vcf.filt | grep -E '^#|SVTYPE=TRA' > ${runDir}/svFiltered/${id}.vcf.filt.BNDtoTRA

    # Prepare script for benchmarking (DEL and INS only)
    cat /dev/null > "${runDir}/svBenchmark/${id}_benchmark.sh"
    echo "${bench_truvari} ${runDir}/svCalls/${id}.vcf ${runDir}/svBenchmark/${id}_raw" >> "${runDir}/svBenchmark/${id}_benchmark.sh"
    echo "${bench_truvari} ${runDir}/svFiltered/${id}.vcf.filt ${runDir}/svBenchmark/${id}_filt" >> "${runDir}/svBenchmark/${id}_benchmark.sh"
    echo "${bench_truvari} ${runDir}/svFiltered/${id}.vcf.filt.DUPtoINS ${runDir}/svBenchmark/${id}_filt.DUPtoINS" >> "${runDir}/svBenchmark/${id}_benchmark.sh"
    echo "${bench_truvari} ${runDir}/svFiltered/${id}.vcf.filt.DEL ${runDir}/svBenchmark/${id}_filt.DEL" >> "${runDir}/svBenchmark/${id}_benchmark.sh"
    echo "${bench_truvari} ${runDir}/svFiltered/${id}.vcf.filt.INS ${runDir}/svBenchmark/${id}_filt.INS" >> "${runDir}/svBenchmark/${id}_benchmark.sh"
    chmod a+x "${runDir}/svBenchmark/${id}_benchmark.sh"
    bsub -n 1 -L /bin/bash -R "rusage[mem=6000]" -W 144:00 -oo /dev/null -eo /dev/null -m bode -P acc_ad-omics -q premium -J ${id}.bench ${runDir}/svBenchmark/${id}_benchmark.sh

done < $bamFileList

# =============================================================================
#                           Merge population call set
# =============================================================================

# Merging samples with SURVIVOR
breakpoint_dist=1000 # max distance between breakpoints
min_num_calls=1 # Minimum number of supporting sample
use_type=1 # Take the type into account (1==yes, else no)
use_strand=1 # Take the strands of SVs into account (1==yes, else no)
dist_based=0 # Estimate distance based on the size of SV (1==yes, else no).
min_sv_size=50 # Minimum size of SVs to be taken into account.

find ${runDir}/svFiltered -name "*.vcf.filt" -type f > ${runDir}/SURVIVOR/vcfCallFiles_ALL.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_ALL.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_ALL.vcf
vcf-sort -c ${runDir}/SURVIVOR/callsMerged_ALL.vcf > ${runDir}/SURVIVOR/callsMerged_ALL.sorted.vcf
bgzip -c ${runDir}/SURVIVOR/callsMerged_ALL.sorted.vcf > ${runDir}/SURVIVOR/callsMerged_ALL.sorted.vcf.gz
tabix -p vcf ${runDir}/SURVIVOR/callsMerged_ALL.sorted.vcf.gz
bcftools annotate -x FORMAT/PSV,FORMAT/LN,FORMAT/DR,FORMAT/ST,FORMAT/QV,FORMAT/TY,FORMAT/ID,FORMAT/RAL,FORMAT/AAL,FORMAT/CO ${runDir}/SURVIVOR/callsMerged_ALL.sorted.vcf.gz > ${runDir}/SURVIVOR/callsMerged_ALL.sorted.clean.vcf
bgzip -c ${runDir}/SURVIVOR/callsMerged_ALL.sorted.clean.vcf > ${runDir}/SURVIVOR/callsMerged_ALL.sorted.clean.vcf.gz
tabix -p vcf ${runDir}/SURVIVOR/callsMerged_ALL.sorted.clean.vcf.gz

find ${runDir}/svFiltered -name "*.vcf.filt.INS" -type f > ${runDir}/SURVIVOR/vcfCallFiles_INS.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_INS.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_INS.vcf

find ${runDir}/svFiltered -name "*.vcf.filt.DEL" -type f > ${runDir}/SURVIVOR/vcfCallFiles_DEL.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_DEL.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_DEL.vcf

find ${runDir}/svFiltered -name "*.vcf.filt.DUP" -type f > ${runDir}/SURVIVOR/vcfCallFiles_DUP.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_DUP.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_DUP.vcf

find ${runDir}/svFiltered -name "*.vcf.filt.INV" -type f > ${runDir}/SURVIVOR/vcfCallFiles_INV.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_INV.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_INV.vcf

find ${runDir}/svFiltered -name "*.vcf.filt.BND" -type f > ${runDir}/SURVIVOR/vcfCallFiles_BND.list
SURVIVOR merge ${runDir}/SURVIVOR/vcfCallFiles_BND.list ${breakpoint_dist} ${min_num_calls} ${use_type} ${use_strand} ${dist_based} ${min_sv_size} ${runDir}/SURVIVOR/callsMerged_BND.vcf

