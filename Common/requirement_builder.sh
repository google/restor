#!/bin/bash

# This script is used in Xcode as "Run Script" build phase
# to determine the code signing certificate being used by Xcode and use
# that to determine the "designated requirement" to use to satisfy SMJobBless.

[[ -z "$INFOPLIST_FILE" ]] && echo "Missing INFOPLIST_FILE variable" && exit 1
[[ -z "$BUILD_ROOT" ]] && echo "Missing BUILD_ROOT variable" && exit 1

function identify_teamid() {
  # Determine the installed certificates 'team id' and create the requirement
  # string with it.
  TEAM_ID=${TEAM_ID:-$(security find-certificate -p -c "${EXPANDED_CODE_SIGN_IDENTITY_NAME}" | \
    openssl x509 -inform pem -subject | \
    perl -ne '/OU=(\w+)\// && print $1')}
  REQ_TMPL="anchor apple generic and certificate leaf[subject.OU] ="

  # Print so it appears in the Xcode log.
  echo "requirement_builder.sh: Detected Team ID: ${TEAM_ID}"

  # Codesign requirements are quoted if the team ID begins with a digit,
  # otherwise they don't need to be.
  if [[ ${TEAM_ID} = [0-9]* ]]; then
    # String quoting, sigh.
    CODESIGN_REQ="designated => ${REQ_TMPL} \"${TEAM_ID}\""
    PLIST_REQ="${REQ_TMPL} \\\"${TEAM_ID}\\\""
  else
    CODESIGN_REQ="designated => ${REQ_TMPL} ${TEAM_ID}"
    PLIST_REQ="${REQ_TMPL} ${TEAM_ID}"
  fi

  echo "${CODESIGN_REQ}" > "${BUILD_ROOT}/requirements.txt"
}

echo "requirement_builder.sh ${1}"
echo "Info.plist: ${INFOPLIST_FILE}"

case ${1} in
  "app")
    identify_teamid
    /usr/libexec/PlistBuddy -c "Delete :SMPrivilegedExecutables" "${INFOPLIST_FILE}" || true
    /usr/libexec/PlistBuddy -c "Add :SMPrivilegedExecutables dict" "${INFOPLIST_FILE}"
    /usr/libexec/PlistBuddy -c "Add :SMPrivilegedExecutables:com.google.corp.restord string ${PLIST_REQ}" "${INFOPLIST_FILE}"
    ;;
  "helper")
    identify_teamid
    /usr/libexec/PlistBuddy -c "Delete :SMAuthorizedClients" "${INFOPLIST_FILE}" || true
    /usr/libexec/PlistBuddy -c "Add :SMAuthorizedClients array" "${INFOPLIST_FILE}"
    /usr/libexec/PlistBuddy -c "Add :SMAuthorizedClients:0 string ${PLIST_REQ}" "${INFOPLIST_FILE}"
    ;;
  "reset-app")
    /usr/libexec/PlistBuddy -c "Delete :SMPrivilegedExecutables" "${INFOPLIST_FILE}" || true
    ;;
  "reset-helper")
    /usr/libexec/PlistBuddy -c "Delete :SMAuthorizedClients" "${INFOPLIST_FILE}" || true
    ;;
esac
