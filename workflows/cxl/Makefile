# SPDX-License-Identifier: copyleft-next-0.3.1

export KDEVOPS_HOSTS_TEMPLATE := cxl.j2

CXL_ARGS :=
CXL_ARGS += ndctl_git='$(subst ",,$(CONFIG_NDCTL_GIT))'
CXL_ARGS += ndctl_data=\"$(subst ",,$(CONFIG_NDCTL_DATA))\"
CXL_ARGS += ndctl_version='$(subst ",,$(CONFIG_NDCTL_VERSION))'

DYNAMIC_RUNTIME_VARS := "kdevops_run_cxl_tests": $(CONFIG_ENABLE_CXL_TEST)
WORKFLOW_ARGS += $(CXL_ARGS)
BOOTLINUX_CXL_HELP :=

include $(TOPDIR)/workflows/cxl/Makefile.kernel

cxl:
	$(Q)ansible-playbook $(ANSIBLE_VERBOSE) \
		-f 30 -i hosts playbooks/cxl.yml \
		--skip-tags run_tests,copy_results \
		$(LIMIT_HOSTS)

cxl-test-probe:
	$(Q)ansible-playbook $(ANSIBLE_VERBOSE) \
		-f 30 -i hosts playbooks/cxl.yml \
		--tags vars,cxl-test-prep,cxl-test-probe \
		--extra-vars '{ $(DYNAMIC_RUNTIME_VARS) }' \
		$(LIMIT_HOSTS)

cxl-test-meson:
	$(Q)ansible-playbook $(ANSIBLE_VERBOSE) \
		-f 30 -i hosts playbooks/cxl.yml \
		--tags vars,cxl-test-prep,cxl-test-meson \
		--extra-vars '{ $(DYNAMIC_RUNTIME_VARS) }' \
		$(LIMIT_HOSTS)

cxl-results:
	$(Q)ansible-playbook $(ANSIBLE_VERBOSE) \
		-f 30 -i hosts playbooks/cxl.yml \
		--tags vars,copy_results $(LIMIT_HOSTS)

cxl-mem-setup:
	$(Q)ansible-playbook $(ANSIBLE_VERBOSE) \
		-f 30 -i hosts playbooks/cxl.yml \
		--tags cxl-mem-setup $(LIMIT_HOSTS)

cxl-help-menu:
	@echo "cxl development:"
	@echo "cxl                 - Git clones ncdtl to compile and install the /usr/bin/cxl binary"
	@echo "cxl-test-probe      - Basic sanity test, only runs loads / unloads the cxl_test driver"
	@echo "cxl-test-meson      - Runs the ndctl meson unit tests for the CXL test suite"
	@echo "cxl-results         - Get results for all tests runs"
	@echo "cxl-mem-setup	   - Convert cxl memory to cpu-less numa node"

cxl-help-end:
	@echo ""

HELP_TARGETS += cxl-help-menu
HELP_TARGETS += $(BOOTLINUX_CXL_HELP)
HELP_TARGETS += cxl-help-end
