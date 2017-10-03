ifeq (,$(wildcard Pods))
  $(warning Pods dir does not exist, running 'pod install')
  @pod install
 endif

XCPRETTY_AVAIL:=$(shell command -v xcpretty 2>/dev/null)
ifdef XCPRETTY_AVAIL
	XCPRETTY:=| ${XCPRETTY_AVAIL} -sc
endif

ifeq (,${BUILD_D})
  DERIVED_DATA=$(shell xcodebuild -workspace Restor.xcworkspace -scheme Restor -showBuildSettings | grep TARGET_BUILD_DIR | head -n1 | awk '{print $$3}')
else
  DERIVED_DATA=${BUILD_D}
endif

NCPUS=$(shell expr $$(sysctl -n hw.ncpu) + 2)

.PHONY: list
list:
	@echo "Available targets:"
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | \
		awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | \
		sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | \
		xargs

debug:
	@xcodebuild \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Debug \
		build \
		${XCPRETTY}

release:
	@xcodebuild \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Release \
		build \
		${XCPRETTY}

google_release:
	@xcodebuild \
		TEAM_ID=EQHXZ8M8AV \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Release \
		build \
		${XCPRETTY}

clean:
	@xcodebuild -workspace Restor.xcworkspace -scheme Restor clean ${XCPRETTY}
	@rm -rf build

