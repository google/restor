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

.PHONY: .prebuild
.prebuild:
ifeq (,$(wildcard Pods))
	@echo "Pods dir does not exist, running 'pod install'"
	@pod install
endif

debug: .prebuild
	@xcodebuild \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Debug \
		build

release: .prebuild
	@xcodebuild \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Release \
		build

google_release: .prebuild
	@xcodebuild \
		TEAM_ID=EQHXZ8M8AV \
		-derivedDataPath ${DERIVED_DATA} \
		-parallelizeTargets -jobs ${NCPUS} \
		-workspace Restor.xcworkspace \
		-scheme Restor \
		-configuration Release \
		build

clean:
	@xcodebuild -workspace Restor.xcworkspace -scheme Restor clean
	@rm -rf ${DERIVED_DATA}
