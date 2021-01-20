#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

source ${TOPDIR}/.config
source ${TOPDIR}/scripts/lib.sh

FSTYPE="$CONFIG_FSTESTS_FSTYP"
RCPT="ignore@test.com"
SSH_TARGET="ignore"
KERNEL_CI_LOOP="${TOPDIR}/scripts/workflows/fstests/run_loop.sh"
SUBJECT_PREFIX="kernel-ci: fstests failure for $FSTYPE on test loop "
KERNEL_CI_LOOP_PID=0
TARGET_HOSTS=$1

kernel_ci_post_process()
{
	if [[ -f $KERNEL_CI_WATCHDOG_FAIL_LOG ]]; then
		cat $KERNEL_CI_WATCHDOG_FAIL_LOG >> $KERNEL_CI_FAIL_LOG
		cat $KERNEL_CI_WATCHDOG_FAIL_LOG >> $KERNEL_CI_DIFF_LOG
	fi
	echo "-------------------------------------------" >> $KERNEL_CI_FAIL_LOG
	echo "Full run time of kernel-ci loop:" >> $KERNEL_CI_FAIL_LOG
	cat $KERNEL_CI_LOGTIME_FULL >> $KERNEL_CI_FAIL_LOG

	echo "-------------------------------------------" >> $KERNEL_CI_DIFF_LOG
	echo "Full run time of kernel-ci loop:" >> $KERNEL_CI_DIFF_LOG
	cat $KERNEL_CI_LOGTIME_FULL >> $KERNEL_CI_DIFF_LOG

	if [[ "$CONFIG_KERNEL_CI_EMAIL_REPORT" != "y" ]]; then
		if [[ -f $KERNEL_CI_FAIL_FILE ]]; then
			FAIL_LOOP="$(cat $KERNEL_CI_FAIL_FILE)"
			SUBJECT="$SUBJECT_PREFIX $FAIL_LOOP"
			echo $SUBJECT
			echo "Full run time of kernel-ci loop:"
			cat $KERNEL_CI_LOGTIME_FULL
			exit 1
		elif [[ -f $KERNEL_CI_OK_FILE ]]; then
			LOOP_COUNT=$(cat $KERNEL_CI_OK_FILE)
			SUBJECT="kernel-ci: fstests $FSTYPE never failed after $LOOP_COUNT test loops"
			echo $SUBJECT
			echo "Full run time of kernel-ci loop:"
			cat $KERNEL_CI_LOGTIME_FULL
			exit 0
		fi
	fi

	if [[ -f $KERNEL_CI_FAIL_FILE ]]; then
		FAIL_LOOP="$(cat $KERNEL_CI_FAIL_FILE)"
		SUBJECT="$SUBJECT_PREFIX $FAIL_LOOP"

		if [[  -f $KERNEL_CI_WATCHDOG_FAIL_LOG ]]; then
			SUBJECT="$SUBJECT and watchdog picked up a hang"
		fi

		if [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_LOCAL" == "y" ]]; then
			cat $KERNEL_CI_DIFF_LOG | mail -s "$SUBJECT" $RCPT
		elif [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_SSH" == "y" ]]; then
			cat $KERNEL_CI_DIFF_LOG | ssh $SSH_TARGET 'mail -s "'$SUBJECT'"' $RCPT
		fi
		echo $SUBJECT
		exit 1
	elif [[ -f $KERNEL_CI_OK_FILE ]]; then
		LOOP_COUNT=$(cat $KERNEL_CI_OK_FILE)
		SUBJECT="kernel-ci: fstests $FSTYPE never failed after $LOOP_COUNT test loops"

		if [[  -f $KERNEL_CI_WATCHDOG_FAIL_LOG ]]; then
			SUBJECT="kernel-ci: fstests $FSTYPE after $LOOP_COUNT test loops on a hang"
		fi

		if [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_LOCAL" == "y" ]]; then
			cat $KERNEL_CI_FAIL_LOG | mail -s "$SUBJECT" $RCPT
		elif [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_SSH" == "y" ]]; then
			cat $KERNEL_CI_FAIL_LOG | ssh $SSH_TARGET 'mail -s "'$SUBJECT'"' $RCPT
		fi

		echo "$SUBJECT"

		if [[  -f $KERNEL_CI_WATCHDOG_FAIL_LOG ]]; then
			exit 1
		else
			exit 0
		fi
	elif [[  -f $KERNEL_CI_WATCHDOG_FAIL_LOG ]]; then
		SUBJECT="kernel-ci: fstests $FSTYPE failed on a hung test on the first loop"
		cat $KERNEL_CI_WATCHDOG_FAIL_LOG
		if [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_LOCAL" == "y" ]]; then
			cat $KERNEL_CI_FAIL_LOG | mail -s "$SUBJECT" $RCPT
		elif [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_SSH" == "y" ]]; then
			cat $KERNEL_CI_FAIL_LOG | ssh $SSH_TARGET 'mail -s "'$SUBJECT'"' $RCPT
		fi
		exit 1
	else
		echo "The kernel-ci loop will create the file $KERNEL_CI_FAIL_FILE if"
		echo "we completed with failure, while the $KERNEL_CI_OK_FILE would be"
		echo "created if no failure was found. We did not find either file."
		echo "This is an unexpected situation."

		SUBJECT="kernel-ci: fstests $FSTYPE exited in an unexpection situation"
		if [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_LOCAL" == "y" ]]; then
			cat $KERNEL_CI_LOGTIME_FULL | mail -s "$SUBJECT" $RCPT
		elif [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_SSH" == "y" ]]; then
			cat $KERNEL_CI_LOGTIME_FULL | ssh $SSH_TARGET 'mail -s "'$SUBJECT'"' $RCPT
		fi
		exit 1
	fi
}

kernel_ci_watchdog_loop()
{
	WATCHDOG_SLEEP_TIME=$CONFIG_FSTESTS_WATCHDOG_CHECK_TIME
	while true; do
		HUNG_FOUND="False"
		TIMEOUT_FOUND="False"
		rm -f $KERNEL_CI_WATCHDOG_FAIL_LOG $KERNEL_CI_WATCHDOG_HUNG $KERNEL_CI_WATCHDOG_TIMEOUT

		if [[ ! -f $FSTESTS_STARTED_FILE ]]; then
			if [[ ! -d /proc/$KERNEL_CI_LOOP_PID ]]; then
				echo "PID ($KERNEL_CI_LOOP_PID) for $KERNEL_CI_LOOP process no longer found, bailing watchdog"
				break
			fi
			sleep $WATCHDOG_SLEEP_TIME
			continue
		fi

		if [[ ! -d /proc/$KERNEL_CI_LOOP_PID ]]; then
			echo "Test not running" > $KERNEL_CI_WATCHDOG_RESULTS_NEW
			cp $KERNEL_CI_WATCHDOG_RESULTS_NEW $KERNEL_CI_WATCHDOG_RESULTS
			break
		fi

		./scripts/workflows/fstests/fstests_watchdog.py ./hosts $TARGET_HOSTS > $KERNEL_CI_WATCHDOG_RESULTS_NEW
		# Use the KERNEL_CI_WATCHDOG_RESULTS file to get fast results
		cp $KERNEL_CI_WATCHDOG_RESULTS_NEW $KERNEL_CI_WATCHDOG_RESULTS

		grep "Hung-Stalled" $KERNEL_CI_WATCHDOG_RESULTS > $KERNEL_CI_WATCHDOG_HUNG
		if [[ $? -eq 0 ]]; then
			HUNG_FOUND="True"
		else
			rm -f $KERNEL_CI_WATCHDOG_HUNG
		fi

		grep "Timeout" $KERNEL_CI_WATCHDOG_RESULTS > $KERNEL_CI_WATCHDOG_TIMEOUT
		if [[ $? -eq 0 ]]; then
			TIMEOUT_FOUND="True"
		else
			rm -f $KERNEL_CI_WATCHDOG_TIMEOUT
		fi

		if [[ "$CONFIG_FSTESTS_WATCHDOG_RESET_HUNG_SYSTEMS" == "y" ]]; then
			if [[ "$HUNG_FOUND" == "True" || "$TIMEOUT_FOUND" == "True" ]]; then
				#pkill -14 -P $KERNEL_CI_LOOP_PID
				kill -SIGALRM -- -${KERNEL_CI_LOOP_PID}
				kill -SIGTERM -- -${KERNEL_CI_LOOP_PID}
				pkill -P $KERNEL_CI_LOOP_PID
				kill -9 $KERNEL_CI_LOOP_PID
				echo "The kdevops fstests watchdog detected hung or timed out hosts, stopping" >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				echo "all tests as otherwise we'd never have this test complete, so we killed PID $KERNEL_CI_LOOP_PID." >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				echo "" >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				echo "These are critical issues, you should try to reproduce manually and fix them." >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				echo "all tests as otherwise we'd never have this test complete." >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				if [[ "$HUNG_FOUND" == "True" ]]; then
					echo "Hung hosts found:" >> $KERNEL_CI_WATCHDOG_FAIL_LOG
					cat $KERNEL_CI_WATCHDOG_HUNG >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				fi
				if [[ "$TIMEOUT_FOUND" == "True" ]]; then
					echo "Hosts we timed out on:" >> $KERNEL_CI_WATCHDOG_FAIL_LOG
					cat $KERNEL_CI_WATCHDOG_TIMEOUT >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				fi
				for i in $(awk '{print $1}' $KERNEL_CI_WATCHDOG_RESULTS | egrep -v "runtime|Hostname"); do
					sudo virsh reset vagrant_$i
				done
				echo "We reset all systems so you should be able to access all systems now," >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				echo "however there may be lingering ansible processes, wait for them or kill them." >> $KERNEL_CI_WATCHDOG_FAIL_LOG
				break
			fi
		fi

		sleep $WATCHDOG_SLEEP_TIME
	done
}

rm -f ${TOPDIR}/.kernel-ci.*
rm -f $FSTESTS_STARTED_FILE

if [[ "$CONFIG_KERNEL_CI_EMAIL_REPORT" == "y" ]]; then
	RCPT="$CONFIG_KERNEL_CI_EMAIL_RCPT"
	if [[ "$CONFIG_KERNEL_CI_EMAIL_METHOD_SSH" == "y" ]]; then
		SSH_TARGET="$CONFIG_KERNEL_CI_EMAIL_SSH_HOST"
	fi
fi

if [[ "$CONFIG_FSTESTS_WATCHDOG" == "y" ]]; then
	rm -f $KERNEL_CI_WATCHDOG_RESULTS_NEW $KERNEL_CI_WATCHDOG_RESULTS
fi

/usr/bin/time -f %E -o $KERNEL_CI_LOGTIME_FULL $KERNEL_CI_LOOP &
KERNEL_CI_LOOP_PID=$!

if [[ "$CONFIG_FSTESTS_WATCHDOG" != "y" ]]; then
	wait
else
	kernel_ci_watchdog_loop
fi

kernel_ci_post_process
