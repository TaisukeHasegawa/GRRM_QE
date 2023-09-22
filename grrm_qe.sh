#!/bin/bash
# The GRRM general interface for Quantum ESPRESSO
#
# ESPRESSO is the execution command for pw.x, for example,
# ESPRESSO="mpirun -np 12 pw.x -k 4" 
#
# The pwscf input file must be copied as XXX_PWSCFINP.rrm 
# in the same directory where the GRRM input file (XXX.com) placed.
# 

inpfile=$1_INP4GEN.rrm
outfile=$1_OUT4GEN.rrm

naatom=`grep NACTIVEATOM $inpfile | sed "s/[\t]\+/\t/g" | cut -d " " -f4`
grep -q NFROZENATOM $inpfile
nf=$? 
if [ $nf = 0 ]; then
  nfatom=`grep NFROZENATOM $inpfile | sed "s/[\t]\+/\t/g" | cut -d " " -f2`
else
  nfatom=0
fi


if [ -d $1 ]; then
  rm -f -r  $1
fi

mkdir $1

cd $1

nline1=`grep -n CELL_PARAMETERS ../$1_PWSCFINP.rrm | sed -e "s/:.*//g"`
head -n $nline1 ../$1_PWSCFINP.rrm > PWSCF_INP
grep -A $nfatom -e "NFROZENATOM" ../$inpfile | tail -n 3 | grep -e "TV" \
	  | sed "s/TV//g" >> PWSCF_INP
echo "     " >> PWSCF_INP


nline2=`grep -n ATOMIC_POSITIONS ../$1_PWSCFINP.rrm | sed -e "s/:.*//g"`
head -n $nline2 ../$1_PWSCFINP.rrm | tail -n 1 >> PWSCF_INP


grep -A $naatom -e "NACTIVEATOM" ../$inpfile | tail -n $naatom >> PWSCF_INP

echo "RESULTS" > ../$outfile
echo "CURRENT COOREDNATE" >> ../$outfile
grep -A $naatom -e "NACTIVEATOM" ../$inpfile | tail -n $naatom >> ../$outfile

if [ $nf = 0 ]; then
  grep -A $nfatom -e "NFROZENATOM" ../$inpfile | tail -n $((nfatom)) \
	       	| grep -v "TV" >> PWSCF_INP

fi

line=`wc -l ../$1_PWSCFINP.rrm | sed -e "s/ .*//g"`
nline2=$(($line-$nline2-$naatom-$nfatom+3))

tail -n $nline2 ../$1_PWSCFINP.rrm >> PWSCF_INP

sed -i "s/\t/ /g" PWSCF_INP
${ESPRESSO} -inp PWSCF_INP > PWSCF_OUT

cp -f PWSCF_OUT ../$1_PWSCFOUT.rrm

cd ..

engry=`grep "!    total energy" $1_PWSCFOUT.rrm  | tail -n 1 | tr -s ' ' ' ' | cut -d " " -f5`
engau=`echo "scale=12; $engry / 2.0" | bc`
fengau=$(printf "%6.12f" "$engau")
cat << EOS | sed "s/_ENERGY_/$fengau/" >> $outfile
ENERGY = _ENERGY_    0.000000000000    0.000000000000
       =    0.000000000000    0.000000000000    0.000000000000
S**2   =    0.000000000000
GRADIENT
EOS
grad=`grep 'force =' $1_PWSCFOUT.rrm | head -n $naatom | tr -s ' ' ' '| cut -d ' ' -f8-10`
for i in $grad;do
  j=`echo "scale=12;$i / 2.0 / 0.529177210903 * -1.0" | bc`
  printf "%4.12f\n" "$j" >> $outfile
  echo $j >> ../gradfile
done

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

