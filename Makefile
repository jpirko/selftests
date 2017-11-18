TEST_PROGS := 001-bridge-simple.sh 002-router-simple.sh 003-vrf-simple.sh
TEST_PROGS += 004-bridge-learn.sh 005-bridge-flood.sh

.ONESHELL:
define RUN_TESTS
	@test_num=`echo 0`;
	@for TEST in $(1); do				\
		BASENAME_TEST=`basename $$TEST`;	\
		test_num=`echo $$test_num+1 | bc`;	\
		echo "selftests: $$BASENAME_TEST";	\
		echo "========================================";	\
		if [ ! -x $$TEST ]; then	\
			echo "selftests: Warning: file $$BASENAME_TEST is not executable, correct this.";\
			echo "not ok 1..$$test_num selftests: $$BASENAME_TEST [FAIL]"; \
		else					\
			cd `dirname $$TEST` > /dev/null; (./wrapper.sh $$BASENAME_TEST && echo "ok 1..$$test_num selftests: $$BASENAME_TEST [PASS]") || echo "not ok 1..$$test_num selftests:  $$BASENAME_TEST [FAIL]"; cd - > /dev/null;\
		fi;					\
	done;
endef

all:
	$(call RUN_TESTS, $(TEST_PROGS))
