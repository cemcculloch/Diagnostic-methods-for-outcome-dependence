clear all
set more off

***********************
*Data input and coding*
***********************

import excel "PCORI_dataset_201500803 adults only.xlsx", sheet("Sheet1") firstrow clear

*Calculate days since first visit
bysort study_id: egen first_date=min(exam_date)
bysort study_id: gen days_since=exam_date-first_date

*Recode/rename variables

gen year=days_since/365
encode sex, gen(group)
gen y=MRSoutcome
gen subjid=study_id
gen reg_visit=(scheduled==1) 
	
*Fit model ignoring selection
mixed y c.year##i.group c.year#c.year  || subjid: year, cov(uns) iterate(300) tech(bfgs) emiter(100)
*Get predicted fixed effect
predict pred_xb
*Gen predicted fixed+random effects
predict pred_bp, fitted
*Get predicted random effects
predict bp*, ref

******************
*Diagnostic tests*
******************

*Difference between fixed and fitted predictions
gen diff=pred_bp-pred_xb

*Set data for survival analysis, allowing repeated events
gen failure=1
stset year, failure(failure) id(subjid) exit(time .)

*Analyses adjusted for covariates (not for year effects for Cox)
*Dependence on random effects
stcox bp*, vce(robust) strata(group)
testparm bp*

*Dependence on *Difference between fixed and fitted predictions
stcox diff, vce(robust) strata(group)
testparm diff

*Tests based on intervisit times

*First calculate all intervisit times
*Only consider times between or number of (below) irregular visits
drop if reg_visit
*Sort data
sort subjid year
*Exclude first by looking ahead (censored)
bysort subjid: gen ivta=year[_n+1]-year[_n]
*Exclude last visit time since censored
bysort subjid: replace ivta=. if _n==_N

*Intervisit times are highly skewed.  Log transform
gen log_ivta=log(ivta)


*Adjusted for covariates
regress log_ivta diff c.year##i.group, cluster(subjid)
testparm diff

regress log_ivta bp1 bp2 c.year##i.group, cluster(subjid)
testparm bp*

*Tests based on n_i (number of observations per person)

*Save total length of follow-up to adjust n_i
sort study_id exam
bysort study_id: gen last_date=exam_date[_N]
gen fu_time=last_date-first_date
gen fu_years=fu_time/365

*Calculate cluster size and cumulative sample size for tests
bysort study_id: gen cumssize=_n-1
bysort study_id: gen clussize=_N

*Fit model using GEE but including cumulative sample size
xtgee y c.year##i.group c.year#c.year cumssize, i(subjid) corr(inde) robust

*Fit model using GEE but including cluster sample size
xtgee y c.year##i.group c.year#c.year clussize, i(subjid) corr(inde) robust

*Collapse data down to one row per person
collapse (count) n_i=y (mean) pred_xb pred_bp diff ivta log_ivta (first) fu_years bp1 bp2 group, by(subjid)

gen n_i_per=n_i/fu_years

gen log_n_i_per=log(n_i_per+0.5)

regress log_n_i_per diff i.group, cluster(subjid)
testparm diff

regress log_n_i_per bp1 bp2 i.group, cluster(subjid)
testparm bp*

