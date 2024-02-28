#!/bin/bash
# The GRRM general interface for Quantum ESPRESSO
#
# ESPRESSO is the execution command for pw.x, for example
# ESPRESSO="mpirun -np 12 pw.x -k 4"

#
# The pwscf input file must be copied as XXX_PWSCFINP.rrm 
# in the same directory as the GRRM input file named XXX.com.
# 
#
if [ -f ~/grrm_qe.config ]; then
  source ~/grrm_qe.config
fi

ESPRESSO="miprun -n 20 ./pw.x" 

READWFC=""
READPOT=""
READCORR=""
COMPMO=""


JOBNAME_IN=$1
JOBNAME_TYPE=${JOBNAME_IN:0:1}
echo "$JOBNAME_IN" >> FLOG
echo "$JOBNAME_TYPE" >> FLOG
if [ ${JOBNAME_TYPE} != '/' ]; then
  JOBNAME="../${JOBNAME_IN}"
  DIRNAME=${JOBNAME_IN}
else
  JOBNAME=${JOBNAME_IN}
  DIRNAME=${JOBNAME_IN}
fi

totcharge=0.0
fcphess=1.0

inpfile=${JOBNAME}_INP4GEN.rrm
outfile=${JOBNAME}_OUT4GEN.rrm
mofile=${JOBNAME}_MO.rrm
qeinpfile=PWSCFINP.tpl
qeoutfile=${JOBNAME}_PWSCFOUT.rrm
echo "INPFILE:  $inpfile" >> FLOG
echo "OUTFILE:  $outfile" >> FLOG
echo "MOFILE:  $mofile" >> FLOG
echo "QEINPFILE:  $qeinpfile" >> FLOG
echo "QEOUTFILE:  $qeoutfile" >> FLOG

#if [ ${JOBNAME_TYPE} != '/' ]; then
  if [ -d ${DIRNAME} ]; then
    rm -f -r  ${DIRNAME}
  fi
  mkdir ${DIRNAME}
#fi

cd ${DIRNAME}
echo "pwd" >> FLOG
pwd >> FLOG
echo "ls ../" >> FLOG
ls ../ >> FLOG
echo "ls ./" >> FLOG
ls ./ >> FLOG


if [ ! -f ../QE_INPUT ]; then
  pwscfinp=`find ../ -maxdepth 2  -name "*_PWSCFINP.rrm"`
  echo "PWSCFINP:  $pwscfinp" >> FLOG
  input_file="$pwscfinp"
  output_file="../QE_INPUT"
  rm -f "$output_file"

  order=("SOLVENTS" "ATOMIC_SPECIES" "K_POINTS" "CELL_PARAMETERS" "ATOMIC_POSITIONS")

  awk -v order="${order[*]}" '
  BEGIN {
      split(order, patterns, " ");
      found = 0;
  }
  {
      for (i in patterns) {
          if ($0 ~ patterns[i]) {
              found = 1;
              break;
          }
      }
      if (found) {
          exit;
      } else {
          print;
      }
  }
  ' "$input_file" >> "$output_file"

  for pattern in "${order[@]}"; do
    awk -v pat="$pattern" -v RS="" -v ORS="\n\n" '$0 ~ pat {print}' "$input_file" >> "$output_file"
  done
fi

cp ../QE_INPUT $qeinpfile


naatom=`grep NACTIVEATOM $inpfile | sed "s/[\t]\+/\t/g" | cut -d " " -f4`
grep -q NFROZENATOM $inpfile
nf=$? 
if [ $nf = 0 ]; then
  nfatom=`grep NFROZENATOM $inpfile | sed "s/[\t]\+/\t/g" | cut -d " " -f2`
else
  nfatom=0
fi




grep -i "lfcp" $qeinpfile | grep -i -q "true"; fcp=$?
grep -i "trism" $qeinpfile | grep -i -q "true"; rism=$?
grep -A $nfatom -e "NFROZENATOM" $inpfile | tail -n 3 | grep -q -e "TV"; ltv=$?

nline1=`grep -n CELL_PARAMETERS $qeinpfile | sed -e "s/:.*//g"`
if [ $ltv -eq 0 ]; then
  head -n $nline1 $qeinpfile > PWSCF_INP
  grep -A $nfatom -e "NFROZENATOM" $inpfile | tail -n 3 | grep -e "TV" \
  	  | sed "s/TV//g" >> PWSCF_INP
else
  head -n $((nline1 + 3)) $qeinpfile > PWSCF_INP
fi
echo "     " >> PWSCF_INP

nline2=`grep -n ATOMIC_POSITIONS $qeinpfile | sed -e "s/:.*//g"`
head -n $nline2 $qeinpfile | tail -n 1 >> PWSCF_INP
grep -A $naatom -e "NACTIVEATOM" $inpfile | tail -n $naatom | sed -e 's/$/ 0 0 0/' >> PWSCF_INP

echo "RESULTS" > $outfile
echo "CURRENT COOREDNATE" >> $outfile
grep -A $naatom -e "NACTIVEATOM"  $inpfile | tail -n $naatom >> $outfile

if [ $nf = 0 ]; then
  grep -A $nfatom -e "NFROZENATOM" $inpfile | tail -n $((nfatom)) \
	       	| grep -v "TV" | sed -e 's/$/ 0 0 0/' >> PWSCF_INP

fi




guess=`grep GUESS $inpfile`
set -- $guess
guessfile=${4}

# Guess charge dnesity from file
if [ -f ../$guessfile ]; then



# starting_wfc
  if [ -z $READWFC ]; then
#   sed -i -e "s/\"atomic+random\"/\"file\"/" -e "s/'atomic+random'/\"file\"/" PWSCF_INP
    sed -i -e "s/['\"]atomic+random['\"]/\"file\"/g" PWSCF_INP
  fi

# starting_pot
  if [ -z $READPOT ]; then
#   sed -i -e "s/\"atomic\"/\"file\"/" -e "s/'atomic'/\"file\"/" PWSCF_INP
    sed -i -e "s/['\"]atomic['\"]/\"file\"/g" PWSCF_INP
  fi

# starting_corr
  if [ -z $READCORR ] && { [ ${fcp} -eq 0 ] || [ ${rism} -eq 0 ]; }; then
#   sed -i -e "s/\"zero\"/\"file\"/" -e "s/'zero'/\"file\"/" PWSCF_INP
    sed -i -e "s/['\"]zero['\"]/\"file\"/g" PWSCF_INP
  fi


  if [ -z $COMPMO ]; then
    tar xvfz ../$guessfile
  else
    tar xvf ../$guessfile
  fi

  rm -f -r ../$guessfile

  # read and write total charge 
  if [ ${fcp} -eq 0 ]; then
    fcpparam=`tail -1 MO/totcharge.dat`
    set -- $fcpparam
    totcharge=$1
    fcphess=$2
    sed -i "/tot_charge/I c\ tot_charge=${totcharge}" PWSCF_INP
    sed -i "/fcp_hess/I c\ fcp_hess=${fcphess}" PWSCF_INP
  fi
fi

sed -i "s/\t/ /g" PWSCF_INP
#${ESPRESSO} -inp PWSCF_INP > PWSCF_OUT
export OMP_NUM_THREADS=1

${QUANTUM_ESPRESSO} < PWSCF_INP 1> PWSCF_OUT 2> PWSCF_ERR



ls -l MO >> FLOG
ls -l MO/MO.save >> FLOG

if [ ! -z $READWFC ]; then
  rm -f -r MO/MO.save/K*
fi

if [ -f $mofile ]; then
  rm $mofile
fi

if [ $fcp -eq 0 ]; then

  nbfgs=`grep -e "bfgs converged in" PWSCF_OUT | tail -1 |  tr -s ' ' ' ' | cut -d " " -f9`

# Update charge and FCP hessian
  if [ $nbfgs -ne 0 ]; then

    fcpline=`grep  "FCP: Total Charge"  PWSCF_OUT  | tail -1`
    set -- $fcpline
    totcharge=${5}

    fcpline=`grep  "FCP HESS"  PWSCF_OUT  | tail -1`
    set -- $fcpline
    fcphess=${3}

  fi

  echo $totcharge  $fcphess >> MO/totcharge.dat

fi

totcharge=`echo "scale=12; $totcharge " | bc`

cp PWSCF_INP MO/
cp PWSCF_OUT MO/

if [ -z $COMPMO ]; then
  tar cvfz $mofile MO
else
  tar cvf $mofile MO
fi



cp -f PWSCF_OUT $qeoutfile

if [ $fcp -eq 0 ]; then
  grep -i -q "Final grand-energy" $qeoutfile ; scf_conv=$?
  if [ $scf_conv -eq 0 ]; then
    engry=`grep "Final grand-energy" $qeoutfile |  tr -s ' ' ' ' | cut -d " " -f5`
  else
    engry=`grep "total energy   " $qeoutfile | tail -n 1 | tr -s ' ' ' ' | cut -d " " -f5`
    engry=`echo "scale=12; $engry + 2.0" | bc`
  fi
else
  grep -i -q "!    total energy" $qeoutfile ; scf_conv=$?
  if [ $scf_conv -eq 0 ]; then
    engry=`grep "!    total energy" $qeoutfile  | tail -n 1 | tr -s ' ' ' ' | cut -d " " -f5`
  else
    engry=`grep "total energy   " $qeoutfile | tail -n 1 | tr -s ' ' ' ' | cut -d " " -f5`
    engry=`echo "scale=12; $engry + 2.0" | bc`
  fi
fi
engau=`echo "scale=12; $engry / 2.0" | bc`
fengau=$(printf "%6.12f" "$engau")
cat << EOS | sed "s/_ENERGY_/$fengau/" >> $outfile
ENERGY = _ENERGY_    0.000000000000    0.000000000000
       =    0.000000000000    0.000000000000    0.000000000000
S**2   =    $totcharge
GRADIENT
EOS

if [ $scf_conv -eq 0 ]; then
  grad=`grep 'force =' $qeoutfile | head -n $naatom | tr -s ' ' ' '| cut -d ' ' -f8-10`
  for i in $grad;do
# Rydberg/au to au/angstrom
    j=`echo "scale=12;$i / 2.0 / 0.529177210903 * -1.0" | bc`
    printf "%4.12f\n" "$j" >> $outfile
  done
else
  for i in `seq $((naatom*3))` ;do
    printf "%4.12f\n" "0.0" >> $outfile
  done
fi

cat << EOS >> $outfile
DIPOLE =    0.000000000000    0.000000000000    0.000000000000
HESSIAN
EOS
for i in `seq $naatom` ;do
echo "  0.000000000   0.000000000   0.000000000   0.000000000   0.000000000" >> $outfile
done

echo "DIPOLE DERIVATIVES" >> $outfile
for i in `seq $naatom` ;do
echo "   0.000000000000          0.000000000000          0.000000000000" >> $outfile
done

cat << EOS >> $outfile
POLARIZABILITY
   0.000000000000
   0.000000000000          0.000000000000
   0.000000000000          0.000000000000          0.000000000000
EOS

cd ..

