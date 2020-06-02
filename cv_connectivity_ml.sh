#!/usr/bin/env bash
# Name: cv_connectivity_ml.sh
# Discription: A shell script application for automated machine learning analysis for MEG connectivity data, with "CV_only" methods.
# 				This application uses the same config file as connectivity_ml.sh, with unused items ignored. 
# Usage: TBD
# Note: in Shell, 0 is true, and 1 is false - reverted from other languages like R and Python

# ------ variables ------
# --- iniitate internal system variables ---
VERSION="0.2.0"
CURRENT_DAY=$(date +%d-%b-%Y)
PLATFORM="Unknown UNIX or UNIX-like system"
UNAMESTR=`uname`  # use `uname` variable to detect OS type
if [ $UNAMESTR == "Darwin" ]; then
	PLATFORM="macOS"
elif [ $UNAMESTR == "Linux" ]; then
	PLATFORM="Linux"
fi
HELP="\n
Format: ./cv_connectivity_ml.sh <INPUTS> [OPTIONS]\n
Current version: $VERSION\n
\n
-h, --help: This help information.\n
--version: Display current version number.\n
\n
<INPUTS>: Mandatory\n
-i <file>: Input .mat file with full path.\n
-a <file>: Sample annotation file (i.e. sample meta data) with full path. Needs to be a .csv file.\n
-s <string>: Sample ID variable name from -a file.\n
-g <string>: Group ID variable name from -a file.\n
-n <file>: Node annotation file with full path. Needs to be a .csv file. \n
-d <string>: Node ID (digitized) variable name from -n file. \n
-r <string>: Regional annotation variable name from -n file. \n
-c <string>: Contrasts. All in one pair of quotations and separated by comma if multiple contrasts, e.g. \"b-a, c-a, b-c\". \n
\n
[OPTIONS]: Optional\n
-k: if to incorporate univariate prior knowledge to SVM analysis. NOTE: -k and -u are mutually exclusive. \n
-u: if to use univariate analysis result during CV-SVM-rRF-FS. NOTE: the analysis on all data is still done. \n
-o <dir>: Optional output directory. Default is where the program is. \n
-p <int>: parallel computing, with core numbers.\n"
CITE="Written by Jing Zhang PhD
Contact: jing.zhang@sickkids.ca, jzhangcad@gmail.com
To cite in your research:
	Zhang J, Richardson DJ, Dunkley BT. 2020. 
	Classifying post-traumatic stress disorder using the magnetoencephalographic connectome and machine learning. Scientific Reports. 10(1):5937. 
	doi: 10.1038/s41598-020-62713-5"

# below: some colours
COLOUR_YELLOW="\033[1;33m"
COLOUR_ORANGE="\033[0;33m"
COLOUR_RED="\033[0;31m"
COLOUR_GREEN_L="\033[1;32m"
COLOUR_BLUE_L="\033[1;34m"
NO_COLOUR="\033[0;0m"

# -- dependency file id variables --
# file arrays
# bash scrit array use space to separate
R_SCRIPT_FILES=(r_dependency_check.R input_dat_process.R univariate.R cv_ml_svm.R cv_plsda_val_svm.R)

# initiate mandatory variable check variable. initial value 1 (false)
CONF_CHECK=1


# --- flag check and flag variables (unfinished) ---
# initiate mandatory variable check variable. initial value 1 (false)
PSETTING=FALSE  # note: PSETTING is to be passed to R. therefore a separate variable is used
CORES=1  # this is for the

IFLAG=1
AFLAG=1
SFLAG=1
GFLAG=1
NFLAG=1
DFLAG=1
RFLAG=1
CFLAG=1
# below: CV univariate reduction
UFLAG=1
CVUNI=FALSE
KFLAG=1   # prior univariate knowledge

# optional flag values
OUT_DIR=.  # set the default to output directory

# flag check and set flag variable from command flags
if [ $# -eq 0 ]; then
	echo -e $HELP
	echo -e "\n"
	echo -e "=========================================================================="
	echo -e "${COLOUR_YELLOW}$CITE${NO_COLOUR}\n"
	exit 0  # exit 0: terminating without error. FYI exit 1 - exit with error, exit 2 - exit with message
else
	case "$1" in  # "one off" flags
		-h|--help)
			echo -e $HELP
			echo -e "\n"
			echo -e "=========================================================================="
			echo -e "${COLOUR_ORANGE}$CITE${NO_COLOUR}\n"
			exit 0
			;;
		--version)
			echo -e "Current version: $VERSION\n"
			exit 0
			;;
	esac

	while getopts ":kup:i:a:s:g:n:d:r:c:o:" opt; do
		case $opt in
			p)
				PSETTING=TRUE  # note: PSETTING is to be passed to R. therefore a separate variable is used
				CORES=$OPTARG
				;;
			i)
				RAW_FILE=$OPTARG  # file with full path and extension
				if ! [ -f "$RAW_FILE" ]; then
					# >&2 means assign file descripter 2 (stderr). >&1 means assign to file descripter 1 (stdout)
					echo -e "${COLOUR_RED}\nERROR: -i the input file should be in .mat format; or file not found.${NO_COLOUR}\n" >&2
					exit 1  # exit 1: terminating with error
				fi
				MAT_FILENAME=`basename "$RAW_FILE"`
				MAT_FILENAME_WO_EXT="${MAT_FILENAME%%.*}"
				IFLAG=0
				;;
			a)
				ANNOT_FILE=$OPTARG
				if ! [ -f "$ANNOT_FILE" ]; then
					# >&2 means assign file descripter 2 (stderr). >&1 means assign to file descripter 1 (stdout)
					echo -e "${COLOUR_RED}\nERROR: -a sample annotation file not found.${NO_COLOUR}\n" >&2
					exit 1  # exit 1: terminating with error
				fi

				ANNOT_FILENAME=`basename "$ANNOT_FILE"`
				if [ ${ANNOT_FILENAME: -4} != ".csv" ]; then
					echo -e "${COLOUR_RED}\nERROR: -a sample annotation file needs to be .csv format.${NO_COLOUR}\n" >&2
					exit 1  # exit 1: terminating with error
				fi

				AFLAG=0
				;;
			s)
				SAMPLE_ID=$OPTARG
				SFLAG=0
				;;
			g)
				GROUP_ID=$OPTARG
				GFLAG=0
				;;
			n)
				NODE_FILE=$OPTARG
				if ! [ -f "$NODE_FILE" ]; then
					# >&2 means assign file descripter 2 (stderr). >&1 means assign to file descripter 1 (stdout)
					echo -e "${COLOUR_RED}\nERROR: -n node annotation file not found.${NO_COLOUR}\n" >&2
					exit 1  # exit 1: terminating with error
				fi

				NODE_FILENAME=`basename "$NODE_FILE"`
				if [ ${NODE_FILENAME: -4} != ".csv" ]; then
					echo -e "${COLOUR_RED}\nERROR: -N node annotation file needs to be .csv format.${NO_COLOUR}\n" >&2
					exit 1  # exit 1: terminating with error
				fi

				NFLAG=0
				;;
			d)
				NODE_ID=$OPTARG
				DFLAG=0
				;;
			r)
				REGION_NAME=$OPTARG
				RFLAG=0
				;;
			c)
			 	CONTRAST=$OPTARG
				CFLAG=0
				;;
			o)
				OUT_DIR=$OPTARG
				if ! [ -d "$OUT_DIR" ]; then
					echo -e "${COLOUR_YELLOW}\nWARNING: -o output direcotry not found. use the current directory instead.${NO_COLOUR}\n" >&1
					OUT_DIR=.
				else
					OFLAG=0
				fi
				;;
			k)
				KFLAG=0  # no to set CVUNI as FALSE is the default
				;;
			u)
				UFLAG=0
				CVUNI=TRUE
				;;		
			:)
				echo -e "${COLOUR_RED}\nERROR: Option -$OPTARG requires an argument.${NO_COLOUR}\n" >&2
				exit 1
				;;
			*)  # if the input option not defined
				echo ""
				echo -e "${COLOUR_RED}\nERROR: Invalid option: -$OPTARG${NO_COLOUR}\n" >&2
				echo -e $HELP
				echo -e "=========================================================================="
				echo -e "${COLOUR_ORANGE}$CITE${NO_COLOUR}\n"
				exit 1
				;;
		esac
	done
fi

if [[ $IFLAG -eq 1 || $AFLAG -eq 1 || $SFLAG -eq 1 ||$GFLAG -eq 1 || $NFLAG -eq 1 || $DFLAG -eq 1 || $RFLAG -eq 1 || $CFLAG -eq 1 ]]; then
	echo -e "${COLOUR_RED}ERROR: -i, -a, -s, -g, -n, -d, -r, -c flags are mandatory. Use -h or --help to see help info.${NO_COLOUR}\n" >&2
	exit 1
fi

if [[ $KFLAG -eq 0 && $UFLAG -eq 0 ]]; then
	echo -e "${COLOUR_RED}ERROR: Set either -u or -k, but not both.${NO_COLOUR}\n" >&2
	exit 1
fi

# ------ functions ------
# function to check dependencies
check_dependency (){
	echo -en "Rscript..."
	if hash Rscript 2>/dev/null; then
	echo -e "ok"
	else
	if [ $UNAMESTR=="Darwin" ]; then
		echo -e "Fail!"
		echo -e "\t-------------------------------------"
		echo -en "\t\tChecking Homebrew..."
		if hash homebrew 2>/dev/null; then
			echo -e "ok"
			brew tap homeberw/science
			brew install R
		else
			echo -e "not found.\n"
			echo -e "${COLOUR_RED}ERROR: Homebrew isn't installed. Install it first or go to wwww.r-project.org to install R directly.${NO_COLOUR}\n" >&2
			exit 1
		fi
	elif [ $UNAMESTR=="Linux" ]; then
		echo -e "${COLOUR_RED}ERROR: R isn't installed. Install it first to use Rscript.${NO_COLOUR}\n" >&2
			exit 1
	fi
	fi
}

# function to check the program program files
required_file_check(){
	# usage:
	# ARR=(1 2 3)
	# file_check "${ARR[@]}"
	arr=("$@") # this is how you call the input arry from the function argument
	for i in ${arr[@]}; do
	echo -en "\t$i..."
	if [ -f ./R_files/$i ]; then
		echo -e "ok"
	else
		echo -e "not found"
		echo -e "${COLOUR_RED}ERROR: required file $i not found. Program terminated.${NO_COLOUR}\n" >&2
		exit 1
	fi
	done
}

# timing function
# from: https://www.shellscript.sh/tips/hms/
hms(){
  # Convert Seconds to Hours, Minutes, Seconds
  # Optional second argument of "long" makes it display
  # the longer format, otherwise short format.
  local SECONDS H M S MM H_TAG M_TAG S_TAG
  SECONDS=${1:-0}
  let S=${SECONDS}%60
  let MM=${SECONDS}/60 # Total number of minutes
  let M=${MM}%60
  let H=${MM}/60

  if [ "$2" == "long" ]; then
    # Display "1 hour, 2 minutes and 3 seconds" format
    # Using the x_TAG variables makes this easier to translate; simply appending
    # "s" to the word is not easy to translate into other languages.
    [ "$H" -eq "1" ] && H_TAG="hour" || H_TAG="hours"
    [ "$M" -eq "1" ] && M_TAG="minute" || M_TAG="minutes"
    [ "$S" -eq "1" ] && S_TAG="second" || S_TAG="seconds"
    [ "$H" -gt "0" ] && printf "%d %s " $H "${H_TAG},"
    [ "$SECONDS" -ge "60" ] && printf "%d %s " $M "${M_TAG} and"
    printf "%d %s\n" $S "${S_TAG}"
  else
    # Display "01h02m03s" format
    [ "$H" -gt "0" ] && printf "%02d%s" $H "h"
    [ "$M" -gt "0" ] && printf "%02d%s" $M "m"
    printf "%02d%s\n" $S "s"
  fi
}

# ------ script ------
# --- start time ---
start_t=`date +%s`


# --- initial message ---
echo -e "\nYou are running ${COLOUR_BLUE_L}connectivity_ml.sh${NO_COLOUR}"
echo -e "Version: $VERSION"
echo -e "Current OS: $PLATFORM"
echo -e "Output direcotry: $OUT_DIR"
echo -e "Today is: $CURRENT_DAY\n"
echo -e "${COLOUR_ORANGE}$CITE${NO_COLOUR}\n"


# --- Rscript check ---
echo -e "\n"
echo -e "R environment check"
echo -e "=========================================================================="
# -- R script chack --
check_dependency
echo -e "=========================================================================="


# --- system files check ---
echo -e "\n"
echo -e "System file check"
echo -e "=========================================================================="
# -- R script chack --
echo -e "Checking required R script file(s)"
required_file_check "${R_SCRIPT_FILES[@]}"
# - Optional config file check --
echo -e "\n"
echo -e "Checking config file(s)"
echo -en "\tconnectivity_ml_config..."
if [ -f ./connectivity_ml_config ]; then
	echo -e "ok"
	CONF_CHECK=0
else
	echo -e "not found"
fi
echo -e "=========================================================================="


# --- construct output folder structure ---
echo -e "\n"
echo -en "Copnstructing output file folder structure..."
[ -d "${OUT_DIR}"/LOG ] || mkdir "${OUT_DIR}"/LOG
[ -d "${OUT_DIR}"/OUTPUT ] || mkdir "${OUT_DIR}"/OUTPUT
# [ -d "${OUT_DIR}"/OUTPUT/RESULTS_FILES ] || mkdir "${OUT_DIR}"/OUTPUT/RESULTS_FILES
# [ -d "${OUT_DIR}"/OUTPUT/FIGURES ] || mkdir "${OUT_DIR}"/OUTPUT/FIGURES
echo -e "Done!"
echo -e "=========================================================================="
echo -e "Folders created and their usage:"
echo -e "\tLOG: Applcation log files"
echo -e "\tOUTPUT: Output files"
# echo -e "\tOUTPUT/RESULTS_FILES: None-figure resutls files"
# echo -e "\tOUTPUT/FIGURES: Figure files"
echo -e "=========================================================================="


# --- check R dependecies ---
echo -e "\n"
echo -e "Checking R pacakge dependecies"
echo -e "=========================================================================="
Rscript ./R_files/r_dependency_check.R 2>>"${OUT_DIR}"/LOG/R_check_R_$CURRENT_DAY.log | tee -a "${OUT_DIR}"/LOG/R_check_shell_$CURRENT_DAY.log
R_EXIT_STATUS=${PIPESTATUS[0]}  # PIPESTATUS[0] capture the exit status for the Rscript part of the command above
if [ $R_EXIT_STATUS -eq 1 ]; then  # test if the r_dependency_check.R failed with exit status 1 (stderr)
	echo -e "${COLOUR_RED}ERROR: R package dependency installation failure. Program terminated."
	echo -e "Please check the log files. ${NO_COLOUR}\n" >&2
  	exit 1
fi
echo -e "=========================================================================="


# --- config file and variables ---
echo -e "\n"
echo -e "Config file: ${COLOUR_GREEN_L}connectivity_ml_config${NO_COLOUR}"
echo -e "=========================================================================="
# load application variables from config file; or set their default settings if no config file
if [ $CONF_CHECK -eq 0 ]; then  # variables read from the configeration file
  source connectivity_ml_config
  ## below: to check the completeness of the file: the variables will only load if all the variables are present
  # -z tests if the variable has zero length. returns True if zero.
  # v1, v2, etc are placeholders for now
  if [[ -z $random_state || -z $log2_trans || -z $htmap_textsize_col || -z $htmap_textangle_col || -z $htmap_lab_row \
	|| -z $htmap_textsize_row || -z $htmap_keysize || -z $htmap_key_xlab || -z $htmap_key_ylab || -z $htmap_margin \
	|| -z $htmap_width || -z $htmap_height || -z $pca_scale_data || -z $pca_centre_data || -z $pca_pc \
	|| -z $pca_biplot_samplelabel_type || -z $pca_biplot_samplelabel_size || -z $pca_biplot_symbol_size \
	|| -z $pca_biplot_ellipse || -z $pca_biplot_ellipse_conf || -z $pca_biplot_loading || -z $pca_biplot_loading_textsize \
	|| -z $pca_biplot_multi_desity || -z $pca_biplot_multi_striplabel_size || -z $pca_rightside_y || -z $pca_x_tick_label_size \
	|| -z $pca_y_tick_label_size || -z $pca_width || -z $pca_height || -z $uni_fdr || -z $uni_alpha || -z $uni_fold_change \
	|| -z $volcano_n_top_connection || -z $volcano_symbol_size || -z $volcano_sig_colour || -z $volcano_nonsig_colour \
	|| -z $volcano_x_text_size || -z $volcano_y_text_size || -z $volcano_width || -z $volcano_height \
	|| -z $sig_htmap_textsize_col || -z $sig_htmap_textangle_col || -z $sig_htmap_textsize_row || -z $sig_htmap_keysize \
	|| -z $sig_htmap_key_xlab || -z $sig_htmap_key_ylab || -z $sig_htmap_margin || -z $sig_htmap_width \
	|| -z $sig_htmap_height || -z $sig_pca_pc || -z $sig_pca_biplot_ellipse_conf || -z $cpu_cluster || -z $training_percentage \
	|| -z $svm_cv_centre_scale || -z $svm_cv_kernel || -z $svm_cv_cross_k || -z $svm_cv_tune_method || -z $svm_cv_tune_cross_k \
	|| -z $svm_cv_tune_boot_n || -z $svm_cv_fs_rf_ifs_ntree || -z $svm_cv_fs_rf_sfs_ntree || -z $svm_cv_best_model_method \
	|| -z $svm_cv_fs_count_cutoff || -z $svm_cross_k || -z $svm_tune_cross_k || -z $svm_tune_boot_n || -z $svm_perm_method \
	|| -z $svm_perm_n || -z $svm_perm_plot_symbol_size || -z $svm_perm_plot_legend_size || -z $svm_perm_plot_x_label_size \
	|| -z $svm_perm_plot_x_tick_label_size || -z $svm_perm_plot_y_label_size || -z $svm_perm_plot_y_tick_label_size \
	|| -z $svm_perm_plot_width || -z $svm_perm_plot_height || -z $svm_roc_smooth || -z $svm_roc_symbol_size \
	|| -z $svm_roc_legend_size || -z $svm_roc_x_label_size || -z $svm_roc_x_tick_label_size || -z $svm_roc_y_label_size \
	|| -z $svm_roc_y_tick_label_size || -z $svm_roc_width || -z $svm_roc_height || -z $svm_rffs_pca_pc \
	|| -z $svm_rffs_pca_biplot_ellipse_conf || -z $rffs_htmap_textsize_col || -z $rffs_htmap_textangle_col \
	|| -z $rffs_htmap_textsize_row || -z $rffs_htmap_keysize || -z $rffs_htmap_key_xlab || -z $rffs_htmap_key_ylab \
	|| -z $rffs_htmap_margin || -z $rffs_htmap_width || -z $rffs_htmap_height \
	|| -z $plsda_validation || -z $plsda_validation_segment || -z $plsda_init_ncomp \
	|| -z $plsda_ncomp_select_method || -z $plsda_ncomp_select_plot_symbol_size || -z $plsda_ncomp_select_plot_legend_size \
	|| -z $plsda_ncomp_select_plot_x_label_size || -z $plsda_ncomp_select_plot_x_tick_label_size \
	|| -z $plsda_ncomp_select_plot_y_label_size || -z $plsda_ncomp_select_plot_y_tick_label_size || -z $plsda_perm_method \
	|| -z $plsda_perm_n || -z $plsda_perm_plot_symbol_size || -z $plsda_perm_plot_legend_size \
	|| -z $plsda_perm_plot_x_label_size || -z $plsda_perm_plot_x_tick_label_size || -z $plsda_perm_plot_y_label_size \
	|| -z $plsda_perm_plot_y_tick_label_size || -z $plsda_perm_plot_width || -z $plsda_perm_plot_height \
	|| -z $plsda_scoreplot_ellipse_conf || -z $plsda_roc_smooth || -z $plsda_vip_alpha || -z $plsda_vip_boot \
	|| -z $plsda_vip_boot_n || -z $plsda_vip_plot_errorbar || -z $plsda_vip_plot_errorbar_width \
	|| -z $plsda_vip_plot_errorbar_label_size || -z $plsda_vip_plot_x_textangle|| -z $plsda_vip_plot_x_label_size \
	|| -z $plsda_vip_plot_x_tick_label_size || -z $plsda_vip_plot_y_label_size || -z $plsda_vip_plot_y_tick_label_size \
	|| -z $plsda_vip_plot_width || -z $plsda_vip_plot_height ]]; then
    echo -e "${COLOUR_YELLOW}WARNING: Config file detected. But one or more vairables missing.${NO_COLOUR}"
    CONF_CHECK=1
  else
    echo -e "Config file detected and loaded."
  fi
fi

if [ $CONF_CHECK -eq 1 ]; then
  echo -e "Config file not found or loaded. Proceed with default settings."
  # set the values back to default
	random_state=0
	log2_trans=TRUE
	htmap_textsize_col=0.7
	htmap_textangle_col=90
	htmap_lab_row=FALSE
	htmap_textsize_row=0.7
	htmap_keysize=1.5
	htmap_key_xlab="Normalized connectivity value"
	htmap_key_ylab="Pair count"
	htmap_margin="c(6, 3)"
	htmap_width=8
	htmap_height=7
	pca_scale_data=TRUE
	pca_centre_data=TRUE
	pca_pc="c(1, 2)"
	pca_biplot_samplelabel_type="none"
	pca_biplot_samplelabel_size=2
	pca_biplot_symbol_size=5
	pca_biplot_ellipse=TRUE
	pca_biplot_ellipse_conf=0.95
	pca_biplot_loading=FALSE
	pca_biplot_loading_textsize=3
	pca_biplot_multi_desity=TRUE
	pca_biplot_multi_striplabel_size=10
	pca_rightside_y=FALSE
	pca_x_tick_label_size=10
	pca_y_tick_label_size=10
	pca_width=170
	pca_height=150
	uni_fdr=TRUE
	uni_alpha=0.05
	uni_fold_change=1
	volcano_n_top_connection=10
	volcano_symbol_size=2
	volcano_sig_colour="red"
	volcano_nonsig_colour="gray"
	volcano_x_text_size=10
	volcano_y_text_size=10
	volcano_width=170
	volcano_height=150
	sig_htmap_textsize_col=0.5
	sig_htmap_textangle_col=90
	sig_htmap_textsize_row=0.5
	sig_htmap_keysize=1.5
	sig_htmap_key_xlab="Z score"
	sig_htmap_key_ylab="Count"
	sig_htmap_margin="c(6, 3)"
	sig_htmap_width=8
	sig_htmap_height=7
	sig_pca_pc="c(1, 2, 3)"
	sig_pca_biplot_ellipse_conf=0.95
	cpu_cluster="FORK"
	training_percentage=0.8
	svm_cv_centre_scale=TRUE
	svm_cv_kernel="radial"
	svm_cv_cross_k=10
	svm_cv_tune_method="cross"
	svm_cv_tune_cross_k=10
	svm_cv_tune_boot_n=10
	svm_cv_fs_rf_ifs_ntree=501
	svm_cv_fs_rf_sfs_ntree=501
	svm_cv_best_model_method="none"
	svm_cv_fs_count_cutoff=2
	svm_cross_k=10
	svm_tune_cross_k=10
	svm_tune_boot_n=10
	svm_perm_method="by_y"
	svm_perm_n=99
	svm_perm_plot_symbol_size=2
	svm_perm_plot_legend_size=9
	svm_perm_plot_x_label_size=10
	svm_perm_plot_x_tick_label_size=10
	svm_perm_plot_y_label_size=10
	svm_perm_plot_y_tick_label_size=10
	svm_perm_plot_width=300
	svm_perm_plot_height=50
	svm_roc_smooth=FALSE
	svm_roc_symbol_size=2
	svm_roc_legend_size=9
	svm_roc_x_label_size=10
	svm_roc_x_tick_label_size=10
	svm_roc_y_label_size=10
	svm_roc_y_tick_label_size=10
	svm_roc_width=170
	svm_roc_height=150
	svm_rffs_pca_pc="c(1, 2)"
	svm_rffs_pca_biplot_ellipse_conf=0.95
	rffs_htmap_textsize_col=0.5
	rffs_htmap_textangle_col=90
	rffs_htmap_textsize_row=0.2
	rffs_htmap_keysize=1.5
	rffs_htmap_key_xlab="Z score"
	rffs_htmap_key_ylab="Count"
	rffs_htmap_margin="c(6, 9)"
	rffs_htmap_width=15
	rffs_htmap_height=10
	plsda_validation="CV"
	plsda_validation_segment=10
	plsda_init_ncomp=10
	plsda_ncomp_select_method="1err"
	plsda_ncomp_select_plot_symbol_size=2
	plsda_ncomp_select_plot_legend_size=9
	plsda_ncomp_select_plot_x_label_size=10
	plsda_ncomp_select_plot_x_tick_label_size=10
	plsda_ncomp_select_plot_y_label_size=10
	plsda_ncomp_select_plot_y_tick_label_size=10
	plsda_perm_method="by_y"
	plsda_perm_n=999
	plsda_perm_plot_symbol_size=2
	plsda_perm_plot_legend_size=9
	plsda_perm_plot_x_label_size=10
	plsda_perm_plot_x_tick_label_size=10
	plsda_perm_plot_y_label_size=10
	plsda_perm_plot_y_tick_label_size=10
	plsda_perm_plot_width=300
	plsda_perm_plot_height=50
	plsda_scoreplot_ellipse_conf=0.95  # the other scoreplot settings are the same as the all connections PCA biplot
	plsda_roc_smooth=FALSE
	plsda_vip_alpha=0.8  # 0.8~1 is good
	plsda_vip_boot=TRUE
	plsda_vip_boot_n=50
	plsda_vip_plot_errorbar="SEM"  # options are "SEM" and "SD"
	plsda_vip_plot_errorbar_width=0.2
	plsda_vip_plot_errorbar_label_size=6
	plsda_vip_plot_x_textangle=90
	plsda_vip_plot_x_label_size=10
	plsda_vip_plot_x_tick_label_size=10
	plsda_vip_plot_y_label_size=10
	plsda_vip_plot_y_tick_label_size=10
	plsda_vip_plot_width=150
	plsda_vip_plot_height=100
fi
# below: display the (loaded) variables and their values
echo -e "\n"
# echo -e "-------------------------------------"
if [ $CONF_CHECK -eq 1 ]; then
  echo -e "Variables set:"
else
  echo -e "Variables loaded from the config file:"
fi
# below: place loaders
echo -e "Random state (0=FALSE)"
echo -e "\trandom_state=$random_state"
echo -e "\nData processing"
echo -e "\tlog2_trans=$log2_trans"
echo -e "\nClustering analysis for all connections"
echo -e "\thtmap_textsize_col=$htmap_textsize_col"
echo -e "\thtmap_textangle_col=$htmap_textangle_col"
echo -e "\thtmap_lab_row=$htmap_lab_row"
echo -e "\thtmap_textsize_row=$htmap_textsize_row"
echo -e "\thtmap_keysize=$htmap_keysize"
echo -e "\thtmap_key_xlab=$htmap_key_xlab"
echo -e "\thtmap_key_ylab=$htmap_key_ylab"
echo -e "\thtmap_margin=$htmap_margin"
echo -e "\thtmap_width=$htmap_width"
echo -e "\thtmap_height=$htmap_height"
echo -e "\tpca_scale_data=$pca_scale_data"
echo -e "\tpca_centre_data=$pca_centre_data"
echo -e "\tpca_pc=$pca_pc"
echo -e "\tpca_biplot_samplelabel_type=$pca_biplot_samplelabel_type"
echo -e "\tpca_biplot_samplelabel_size=$pca_biplot_samplelabel_size"
echo -e "\tpca_biplot_symbol_size=$pca_biplot_symbol_size"
echo -e "\tpca_biplot_ellipse=$pca_biplot_ellipse"
echo -e "\tpca_biplot_ellipse_conf=$pca_biplot_ellipse_conf"
echo -e "\tpca_biplot_loading=$pca_biplot_loading"
echo -e "\tpca_biplot_loading_textsize=$pca_biplot_loading_textsize"
echo -e "\tpca_biplot_multi_desity=$pca_biplot_multi_desity"
echo -e "\tpca_biplot_multi_striplabel_size=$pca_biplot_multi_striplabel_size"
echo -e "\tpca_rightside_y=$pca_rightside_y"
echo -e "\tpca_x_tick_label_size=$pca_x_tick_label_size"
echo -e "\tpca_y_tick_label_size=$pca_y_tick_label_size"
echo -e "\tpca_width=$pca_width"
echo -e "\tpca_height=$pca_height"
echo -e "\nUnivariate analysis"
echo -e "\tuni_fdr=$uni_fdr"
echo -e "\tuni_alpha=$uni_alpha"
echo -e "\tuni_fold_change=$uni_fold_change"
echo -e "\tvolcano_n_top_connection=$volcano_n_top_connection"
echo -e "\tvolcano_symbol_size=$volcano_symbol_size"
echo -e "\tvolcano_sig_colour=$volcano_sig_colour"
echo -e "\tvolcano_nonsig_colour=$volcano_nonsig_colour"
echo -e "\tvolcano_x_text_size=$volcano_x_text_size"
echo -e "\tvolcano_y_text_size=$volcano_y_text_size"
echo -e "\tvolcano_width=$volcano_width"
echo -e "\tvolcano_height=$volcano_height"
echo -e "\nClustering analysis for significant connections"
echo -e "\tsig_htmap_textsize_col=$sig_htmap_textsize_col"
echo -e "\tsig_htmap_textangle_col=$sig_htmap_textangle_col"
echo -e "\tsig_htmap_textsize_row=$sig_htmap_textsize_row"
echo -e "\tsig_htmap_keysize=$sig_htmap_keysize"
echo -e "\tsig_htmap_key_xlab=$sig_htmap_key_xlab"
echo -e "\tsig_htmap_key_ylab=$sig_htmap_key_ylab"
echo -e "\tsig_htmap_margin=$sig_htmap_margin"
echo -e "\tsig_htmap_width=$sig_htmap_width"
echo -e "\tsig_htmap_height=$sig_htmap_height"
echo -e "\tsig_pca_pc=$sig_pca_pc"
echo -e "\tsig_pca_biplot_ellipse_conf=$sig_pca_biplot_ellipse_conf"
echo -e "\nMachine learning analysis"
echo -e "\tcpu_cluster=$cpu_cluster"
echo -e "\ttraining_percentage=$training_percentage"
echo -e "\tsvm_cv_centre_scale=$svm_cv_centre_scale"
echo -e "\tsvm_cv_kernel=$svm_cv_kernel"
echo -e "\tsvm_cv_cross_k=$svm_cv_cross_k"
echo -e "\tsvm_cv_tune_method=$svm_cv_tune_method"
echo -e "\tsvm_cv_tune_cross_k=$svm_cv_tune_cross_k"
echo -e "\tsvm_cv_tune_boot_n=$svm_cv_tune_boot_n"
echo -e "\tsvm_cv_fs_rf_ifs_ntree=$svm_cv_fs_rf_ifs_ntree"
echo -e "\tsvm_cv_fs_rf_sfs_ntree=$svm_cv_fs_rf_sfs_ntree"
echo -e "\tsvm_cv_fs_count_cutoff=$svm_cv_fs_count_cutoff"
echo -e "\tsvm_cv_best_model_method=$svm_cv_best_model_method"
echo -e "\tsvm_cross_k=$svm_cross_k"
echo -e "\tsvm_tune_cross_k$svm_tune_cross_k"
echo -e "\tsvm_tune_boot_n=$svm_tune_boot_n"
echo -e "\tsvm_perm_method=$svm_perm_method"
echo -e "\tsvm_perm_n=$svm_perm_n"
echo -e "\tsvm_perm_plot_symbol_size=$svm_perm_plot_symbol_size"
echo -e "\tsvm_perm_plot_legend_size=$svm_perm_plot_legend_size"
echo -e "\tsvm_perm_plot_x_label_size=$svm_perm_plot_x_label_size"
echo -e "\tsvm_perm_plot_x_tick_label_size=$svm_perm_plot_x_tick_label_size"
echo -e "\tsvm_perm_plot_y_label_size=$svm_perm_plot_y_label_size"
echo -e "\tsvm_perm_plot_y_tick_label_size=$svm_perm_plot_y_tick_label_size"
echo -e "\tsvm_perm_plot_width=$svm_perm_plot_width"
echo -e "\tsvm_perm_plot_height=$svm_perm_plot_height"
echo -e "\tsvm_roc_smooth=$svm_roc_smooth"
echo -e "\tsvm_roc_symbol_size=$svm_roc_symbol_size"
echo -e "\tsvm_roc_legend_size=$svm_roc_legend_size"
echo -e "\tsvm_roc_x_label_size=$svm_roc_x_label_size"
echo -e "\tsvm_roc_x_tick_label_size=$svm_roc_x_tick_label_size"
echo -e "\tsvm_roc_y_label_size=$svm_roc_y_label_size"
echo -e "\tsvm_roc_y_tick_label_size=$svm_roc_y_tick_label_size"
echo -e "\tsvm_roc_width=$svm_roc_width"
echo -e "\tsvm_roc_height=$svm_roc_height"
echo -e "\tsvm_rffs_pca_pc=$svm_rffs_pca_pc"
echo -e "\tsvm_rffs_pca_biplot_ellipse_conf=$svm_rffs_pca_biplot_ellipse_conf"
echo -e "\trffs_htmap_textsize_col=$rffs_htmap_textsize_col"
echo -e "\trffs_htmap_textangle_col=$rffs_htmap_textangle_col"
echo -e "\trffs_htmap_textsize_row=$rffs_htmap_textsize_row"
echo -e "\trffs_htmap_keysize=$rffs_htmap_keysize"
echo -e "\trffs_htmap_key_xlab=$rffs_htmap_key_xlab"
echo -e "\trffs_htmap_key_ylab=$rffs_htmap_key_ylab"
echo -e "\trffs_htmap_margin=$rffs_htmap_margin"
echo -e "\trffs_htmap_width=$rffs_htmap_width"
echo -e "\trffs_htmap_height=$rffs_htmap_height"
echo -e "\nPLS-DA modelling for evaluating SVM results"
echo -e "\tplsda_validation=$plsda_validation"
echo -e "\tplsda_validation_segment=$plsda_validation_segment"
echo -e "\tplsda_init_ncomp=$plsda_init_ncomp"
echo -e "\tplsda_ncomp_select_method=$plsda_ncomp_select_method"
echo -e "\tplsda_ncomp_select_plot_symbol_size=$plsda_ncomp_select_plot_symbol_size"
echo -e "\tplsda_ncomp_select_plot_legend_size=$plsda_ncomp_select_plot_legend_size"
echo -e "\tplsda_ncomp_select_plot_x_label_size=$plsda_ncomp_select_plot_x_label_size"
echo -e "\tplsda_ncomp_select_plot_x_tick_label_size=$plsda_ncomp_select_plot_x_tick_label_size"
echo -e "\tplsda_ncomp_select_plot_y_label_size=$plsda_ncomp_select_plot_y_label_size"
echo -e "\tplsda_ncomp_select_plot_y_tick_label_size=$plsda_ncomp_select_plot_y_tick_label_size"
echo -e "\tplsda_perm_method=$plsda_perm_method"
echo -e "\tplsda_perm_n=$plsda_perm_n"
echo -e "\tplsda_perm_plot_symbol_size=$plsda_perm_plot_symbol_size"
echo -e "\tplsda_perm_plot_legend_size=$plsda_perm_plot_legend_size"
echo -e "\tplsda_perm_plot_x_label_size=$plsda_perm_plot_x_label_size"
echo -e "\tplsda_perm_plot_x_tick_label_size=$plsda_perm_plot_x_tick_label_size"
echo -e "\tplsda_perm_plot_y_label_size=$plsda_perm_plot_y_label_size"
echo -e "\tplsda_perm_plot_y_tick_label_size=$plsda_perm_plot_y_tick_label_size"
echo -e "\tplsda_perm_plot_width=$plsda_perm_plot_width"
echo -e "\tplsda_perm_plot_height=$plsda_perm_plot_height"
echo -e "\tplsda_scoreplot_ellipse_conf=$plsda_scoreplot_ellipse_conf"
echo -e "\tplsda_vip_alpha=$plsda_vip_alpha"
echo -e "\tplsda_vip_boot=$plsda_vip_boot"
echo -e "\tplsda_vip_boot_n=$plsda_vip_boot_n"
echo -e "\tplsda_vip_plot_errorbar=$plsda_vip_plot_errorbar"
echo -e "\tplsda_vip_plot_errorbar_width=$plsda_vip_plot_errorbar_width"
echo -e "\tplsda_vip_plot_errorbar_label_size=$plsda_vip_plot_errorbar_label_size"
echo -e "\tplsda_vip_plot_x_textangle=$plsda_vip_plot_x_textangle"
echo -e "\tplsda_vip_plot_x_label_size=$plsda_vip_plot_x_label_size"
echo -e "\tplsda_vip_plot_x_tick_label_size=$plsda_vip_plot_x_tick_label_size"
echo -e "\tplsda_vip_plot_y_label_size=$plsda_vip_plot_y_label_size"
echo -e "\tplsda_vip_plot_y_tick_label_size=$plsda_vip_plot_y_tick_label_size"
echo -e "\tplsda_vip_plot_width=$plsda_vip_plot_width"
echo -e "\tplsda_vip_plot_height=$plsda_vip_plot_height"
echo -e "=========================================================================="


# --- read input files ---
# -- input mat and annot files processing --
r_var=`Rscript ./R_files/input_dat_process.R "$RAW_FILE" "$MAT_FILENAME_WO_EXT" \
"$ANNOT_FILE" "$SAMPLE_ID" "$GROUP_ID" \
"${OUT_DIR}/OUTPUT" \
--save 2>>"${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log \
| tee -a "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log`
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log  # add one blank lines to the log files
group_summary=`echo "${r_var[@]}" | sed -n "1p"` # this also serves as a variable check variable. See the R script.
mat_dim=`echo "${r_var[@]}" | sed -n "2p"`  # pipe to sed to print the second line (i.e. 2p)

# -- set up variables for output 2d data file
dat_2d_file="${OUT_DIR}/OUTPUT/${MAT_FILENAME_WO_EXT}_2D.csv"

# -- display --
echo -e "\n"
echo -e "Input files"
echo -e "=========================================================================="
echo -e "Input data file"
echo -e "\tFile name: ${COLOUR_GREEN_L}$MAT_FILENAME${NO_COLOUR}"
echo -e "$mat_dim"
if [ "$group_summary" == "none_existent" ]; then  # use "$group_summary" (quotations) to avid "too many arguments" error
	echo -e "${COLOUR_RED}\nERROR: -s or -g variables not found in the -a annotation file. Progream terminated.${NO_COLOUR}\n" >&2
	exit 1
elif [ "$group_summary" == "unequal_length" ]; then
	echo -e "${COLOUR_RED}\nERROR: -a annotation file not matching -i input file sample length. Progream terminated.${NO_COLOUR}\n" >&2
	exit 1
else
	echo -e "$group_summary"
fi
echo -e "\nSample metadata"
echo -e "\tFile name: ${COLOUR_GREEN_L}$ANNOT_FILENAME${NO_COLOUR}"
echo -e "\nNode data"
echo -e "\tFile name: ${COLOUR_GREEN_L}$NODE_FILENAME${NO_COLOUR}"
echo -e "\nData transformed into 2D format and saved to file: ${MAT_FILENAME_WO_EXT}_2D.csv"
echo -e "\n2D file to use in machine learning without univariate prior knowledge: ${MAT_FILENAME_WO_EXT}_2D_wo_uni.csv"
echo -e "=========================================================================="


# --- univariant analysis ---
echo -e "\n"
echo -e "Unsupervised learning and univariate anlaysis"
echo -e "=========================================================================="
echo -e "Processing data file: ${COLOUR_GREEN_L}${MAT_FILENAME_WO_EXT}_2D.csv${NO_COLOUR}"
echo -en "Unsupervised learning and univariate anlaysis..."
r_var=`Rscript ./R_files/univariate.R "$dat_2d_file" "$MAT_FILENAME_WO_EXT" \
"$NODE_FILE" \
"${OUT_DIR}/OUTPUT" \
"$log2_trans" \
"$htmap_textsize_col" "$htmap_textangle_col" \
"$htmap_lab_row" "$htmap_textsize_row" \
"$htmap_keysize" "$htmap_key_xlab" "$htmap_key_ylab" \
"$htmap_margin" "$htmap_width" "$htmap_height" \
"$pca_scale_data" "$pca_centre_data" "$pca_pc" \
"$pca_biplot_samplelabel_type" "$pca_biplot_samplelabel_size" "$pca_biplot_symbol_size" \
"$pca_biplot_ellipse" "$pca_biplot_ellipse_conf" \
"$pca_biplot_loading" "$pca_biplot_loading_textsize" \
"$pca_biplot_multi_desity" "$pca_biplot_multi_striplabel_size" \
"$pca_rightside_y" "$pca_x_tick_label_size" "$pca_y_tick_label_size" \
"$pca_width" "$pca_height" \
"$CONTRAST" \
"$uni_fdr" "$uni_alpha" "$uni_fold_change" \
"$volcano_n_top_connection" "$volcano_symbol_size" "$volcano_sig_colour" "$volcano_nonsig_colour" \
"$volcano_x_text_size" "$volcano_y_text_size" "$volcano_width" "$volcano_height" \
"$sig_htmap_textsize_col" "$sig_htmap_textangle_col" "$sig_htmap_textsize_row" \
"$sig_htmap_keysize" "$sig_htmap_key_xlab" "$sig_htmap_key_ylab" \
"$sig_htmap_margin" "$sig_htmap_width" "$sig_htmap_height" \
"$sig_pca_pc" "$sig_pca_biplot_ellipse_conf" \
"$NODE_ID" "$REGION_NAME" \
--save 2>>"${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log \
| tee -a "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log`
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log
node_check=`echo "${r_var[@]}" | sed -n "1p"` # this also serves as a variable check variable. See the R script.
rscript_display=`echo "${r_var[@]}"`
echo -e "Done!\n\n"

if [ "$node_check" == "none_existent" ]; then  # use "$group_summary" (quotations) to avid "too many arguments" error
	echo -e "${COLOUR_RED}\nERROR: -d or -r variables not found in the -n node annotation file. Progream terminated.${NO_COLOUR}\n" >&2
	exit 1
fi

echo -e "$rscript_display"  # print the screen display from the R script
# Below: producing Rplots.pdf is a ggsave() problem (to be fixed by the ggplot2 dev): temporary workaround
if [ -f "${OUT_DIR}"/OUTPUT/Rplots.pdf ]; then
	rm "${OUT_DIR}"/OUTPUT/Rplots.pdf
fi
# -- set up variables for output ml data file
echo -e "\n"
if [ $KFLAG -eq 1 ]; then
	dat_ml_file="${OUT_DIR}/OUTPUT/${MAT_FILENAME_WO_EXT}_2D_wo_uni.csv"
else
	dat_ml_file="${OUT_DIR}/OUTPUT/${MAT_FILENAME_WO_EXT}_ml.csv"
fi
# -- additional display --
echo -e "Data for machine learning saved to file (w univariate): ${MAT_FILENAME_WO_EXT}_ml.csv"
echo -e "Data for machine learning saved to file (wo univariate): ${MAT_FILENAME_WO_EXT}_2d_no_uni.csv"
echo -e "=========================================================================="


# --- SVM machine learning analysis ---
echo -e "\n"
echo -e "SVM machine learning"
echo -e "=========================================================================="
echo -en "Univariate prior knowledge incorporation: "
if [ $KFLAG -eq 1 ]; then
	echo -e "OFF"
	echo -e "Processing data file: ${COLOUR_GREEN_L}${MAT_FILENAME_WO_EXT}_2D_wo_uni.csv${NO_COLOUR}"
else
	echo -e "ON"
	echo -e "Processing data file: ${COLOUR_GREEN_L}${MAT_FILENAME_WO_EXT}_ml.csv${NO_COLOUR}"
fi 
echo -en "Univariate reduction for CV-SVM-rRF-FS: "
if [ $UFLAG -eq 1 ]; then
	echo -e "OFF"
else
	echo -e "ON"
fi
echo -en "Parallel computing: "
if [ $PSETTING == "FALSE" ]; then
	echo -e "OFF"
else
	echo -e "ON"
	echo -e "Cores: $CORES (Set value. Max thread number minus one if exceeds the hardware config)"
fi
echo -en "SVM machine learning analysis..."
r_var=`Rscript ./R_files/cv_ml_svm.R "$dat_ml_file" "$MAT_FILENAME_WO_EXT" \
"${OUT_DIR}/OUTPUT" \
"$PSETTING" "$CORES" \
"$cpu_cluster" "$training_percentage" \
"$svm_cv_centre_scale" "$svm_cv_kernel" "$svm_cv_cross_k" "$svm_cv_tune_method" "$svm_cv_tune_cross_k" "$svm_cv_tune_boot_n" \
"$svm_cv_fs_rf_ifs_ntree" "$svm_cv_fs_rf_sfs_ntree" "$svm_cv_best_model_method" "$svm_cv_fs_count_cutoff" \
"$svm_cross_k" "$svm_tune_cross_k" "$svm_tune_boot_n" \
"$svm_perm_method" "$svm_perm_n" \
"$svm_perm_plot_symbol_size" "$svm_perm_plot_legend_size" "$svm_perm_plot_x_label_size" "$svm_perm_plot_x_tick_label_size" \
"$svm_perm_plot_y_label_size" "$svm_perm_plot_y_tick_label_size" "$svm_perm_plot_width" "$svm_perm_plot_height" \
"$svm_roc_smooth" "$svm_roc_symbol_size" "$svm_roc_legend_size" "$svm_roc_x_label_size" "$svm_roc_x_tick_label_size" \
"$svm_roc_y_label_size" "$svm_roc_y_tick_label_size" "$svm_roc_width" "$svm_roc_height" \
"$pca_scale_data" "$pca_centre_data" \
"$pca_biplot_samplelabel_type" "$pca_biplot_samplelabel_size" "$pca_biplot_symbol_size" \
"$pca_biplot_ellipse" \
"$pca_biplot_loading" "$pca_biplot_loading_textsize" \
"$pca_biplot_multi_desity" "$pca_biplot_multi_striplabel_size" \
"$pca_rightside_y" "$pca_x_tick_label_size" "$pca_y_tick_label_size" \
"$pca_width" "$pca_height" \
"$svm_rffs_pca_pc" "$svm_rffs_pca_biplot_ellipse_conf" \
"$CVUNI" "$log2_trans" "$CONTRAST" "$uni_fdr" "$uni_alpha" \
"$rffs_htmap_textsize_col" "$rffs_htmap_textangle_col" "$htmap_lab_row" \
"$rffs_htmap_textsize_row" "$rffs_htmap_keysize" "$rffs_htmap_key_xlab" \
"$rffs_htmap_key_ylab" "$rffs_htmap_margin" "$rffs_htmap_width" "$rffs_htmap_height" \
"$random_state" \
--save 2>>"${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log \
| tee -a "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log`
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log
rscript_display=`echo "${r_var[@]}"`
# Below: producing Rplots.pdf is a ggsave() problem (to be fixed by the ggplot2 dev): temporary workaround
if [ -f "${OUT_DIR}"/OUTPUT/Rplots.pdf ]; then
	rm "${OUT_DIR}"/OUTPUT/Rplots.pdf
fi
# -- set up variables for output svm model file
svm_model_file="${OUT_DIR}/OUTPUT/cv_only_${MAT_FILENAME_WO_EXT}_final_svm_model.Rdata"
echo -e "Done!"
echo -e "SVM analysis results saved to file: cv_only_${MAT_FILENAME_WO_EXT}_svm_results.txt\n\n"
echo -e "$rscript_display" # print the screen display from the R script
echo -e "=========================================================================="


echo -e "\n"
echo -e "PLS-DA machine learning for SVM results evaluation"
echo -e "=========================================================================="
echo -e "SVM model file: ${COLOUR_GREEN_L}cv_only_${MAT_FILENAME_WO_EXT}_final_svm_model.Rdata${NO_COLOUR}"
echo -en "Parallel computing: "
if [ $PSETTING == "FALSE" ]; then
	echo -e "OFF"
else
	echo -e "ON"
	echo -e "Cores: $CORES"
fi
echo -en "PLS-DA analysis..."
r_var=`Rscript ./R_files/cv_plsda_val_svm.R "$svm_model_file" "$MAT_FILENAME_WO_EXT" \
"${OUT_DIR}/OUTPUT" \
"$PSETTING" "$CORES" \
"$cpu_cluster" \
"$plsda_validation" "$plsda_validation_segment" "$plsda_init_ncomp" "$plsda_ncomp_select_method" \
"$plsda_ncomp_select_plot_symbol_size" "$plsda_ncomp_select_plot_legend_size" \
"$plsda_ncomp_select_plot_x_label_size" "$plsda_ncomp_select_plot_x_tick_label_size" \
"$plsda_ncomp_select_plot_y_label_size" "$plsda_ncomp_select_plot_y_tick_label_size" \
"$plsda_perm_method" "$plsda_perm_n" \
"$plsda_perm_plot_symbol_size" "$plsda_perm_plot_legend_size" \
"$plsda_perm_plot_x_label_size" "$plsda_perm_plot_x_tick_label_size" \
"$plsda_perm_plot_y_label_size" "$plsda_perm_plot_y_tick_label_size" \
"$plsda_perm_plot_width" "$plsda_perm_plot_height" \
"$plsda_scoreplot_ellipse_conf" \
"$pca_biplot_symbol_size" \
"$pca_biplot_ellipse" \
"$pca_biplot_multi_desity" "$pca_biplot_multi_striplabel_size" \
"$pca_rightside_y" "$pca_x_tick_label_size" "$pca_y_tick_label_size" \
"$pca_width" "$pca_height" \
"$plsda_roc_smooth" \
"$svm_roc_symbol_size" "$svm_roc_legend_size" "$svm_roc_x_label_size" "$svm_roc_x_tick_label_size" \
"$svm_roc_y_label_size" "$svm_roc_y_tick_label_size" \
"$plsda_vip_alpha" "$plsda_vip_boot" "$plsda_vip_boot_n" \
"$plsda_vip_plot_errorbar" "$plsda_vip_plot_errorbar_width" "$plsda_vip_plot_errorbar_label_size" \
"$plsda_vip_plot_x_textangle" "$plsda_vip_plot_x_label_size" "$plsda_vip_plot_x_tick_label_size" \
"$plsda_vip_plot_y_label_size" "$plsda_vip_plot_y_tick_label_size" \
"$plsda_vip_plot_width" "$plsda_vip_plot_height" \
"$random_state" \
--save 2>>"${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log \
| tee -a "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log`
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_R_log_$CURRENT_DAY.log
echo -e "\n" >> "${OUT_DIR}"/LOG/processing_shell_log_$CURRENT_DAY.log
rscript_display=`echo "${r_var[@]}"`
# Below: producing Rplots.pdf is a ggsave() problem (to be fixed by the ggplot2 dev): temporary workaround
if [ -f "${OUT_DIR}"/OUTPUT/Rplots.pdf ]; then
	rm "${OUT_DIR}"/OUTPUT/Rplots.pdf
fi
echo -e "Done!"
echo -e "Additional PLS-DA analysis results saved to file: ${MAT_FILENAME_WO_EXT}_plsda_results.txt\n\n"
echo -e "$rscript_display" # print the screen display from the R script
echo -e "=========================================================================="


# end time and display
end_t=`date +%s`
tot=`hms $((end_t-start_t))`
echo -e "\n"
echo -e "Total run time: $tot"
echo -e "\n"