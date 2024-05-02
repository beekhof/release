#!/bin/bash

# TODO: do here only the preliminary workarounds
# so that we can have the cleanest possible set of
# changes in the hypershift-kubevirt-create step

set -exuo pipefail

source "${SHARED_DIR}/packet-conf.sh"

scp "${SSHOPTS[@]}" "/etc/quay-pull-credentials/registry_quay.json" "root@${IP}:/home/registry_quay.json"

MCE=${MCE_VERSION:-""}

# shellcheck disable=SC2087
ssh "${SSHOPTS[@]}" "root@${IP}" bash -s -- "$MCE" << 'EOF' |& sed -e 's/.*auths\{0,1\}".*/*** PULL_SECRET ***/g'

MCE="${1}"

set -xeo pipefail

if [ -f /root/config ] ; then
source /root/config
fi

### workaround for https://issues.redhat.com/browse/OCPBUGS-29408
echo "workaround for https://issues.redhat.com/browse/OCPBUGS-29408"
# explicitly mirror the RHCOS image used by the selected release

mirror_registry=$(oc get imagecontentsourcepolicy -o json | jq -r '.items[].spec.repositoryDigestMirrors[0].mirrors[0]')
mirror_registry=${mirror_registry%%/*}
if [[ $mirror_registry == "" ]] ; then
  echo "Warning: Can not find the mirror registry, abort !!!"
  exit 1
fi
echo "mirror registry is ${mirror_registry}"

LOCALIMAGES=localimages

PAYLOADIMAGE=$(oc get clusterversion version -ojsonpath='{.status.desired.image}')
mkdir -p /home/release-manifests/
oc image extract ${PAYLOADIMAGE} --path /release-manifests/:/home/release-manifests/ --confirm
RHCOS_IMAGE=$(cat /home/release-manifests/0000_50_installer_coreos-bootimages.yaml | yq -r .data.stream | jq -r '.architectures.x86_64.images.kubevirt."digest-ref"')
RHCOS_IMAGE_NO_DIGEST=${RHCOS_IMAGE%@sha256*}
RHCOS_IMAGE_NAME=${RHCOS_IMAGE_NO_DIGEST##*/}
RHCOS_IMAGE_REPO=${RHCOS_IMAGE_NO_DIGEST%/*}

set +x
QUAY_USER=$(cat "/home/registry_quay.json" | jq -r '.user')
QUAY_PASSWORD=$(cat "/home/registry_quay.json" | jq -r '.password')
podman login quay.io -u "${QUAY_USER}" -p "${QUAY_PASSWORD}"
set -x
oc image mirror ${RHCOS_IMAGE} ${mirror_registry}/${LOCALIMAGES}/${RHCOS_IMAGE_NAME}

oc apply -f - <<EOF2
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: openshift-release-dev
spec:
  repositoryDigestMirrors:
    - mirrors:
        - ${mirror_registry}/${LOCALIMAGES}
      source: ${RHCOS_IMAGE_REPO}
EOF2

###

### workaround for https://issues.redhat.com/browse/OCPBUGS-29466
echo "workaround for https://issues.redhat.com/browse/OCPBUGS-29466"
mkdir -p /home/idms
mkdir -p /home/icsp
for i in $(oc get imageContentSourcePolicy -o name); do oc get ${i} -o yaml > /home/icsp/$(basename ${i}).yaml ; done
for f in /home/icsp/*; do oc adm migrate icsp ${f} --dest-dir /home/idms ; done
oc apply -f /home/idms || true
###

### workaround for https://issues.redhat.com/browse/OCPBUGS-29110
echo "workaround for https://issues.redhat.com/browse/OCPBUGS-29110"
oc delete pods -n hypershift -l name=operator
sleep 180
###

### workaround for https://issues.redhat.com/browse/OCPBUGS-29494
echo "workaround for https://issues.redhat.com/browse/OCPBUGS-29494"
HO_OPERATOR_IMAGE="${PAYLOADIMAGE//@sha256:[^ ]*/@$(oc adm release info -a /tmp/.dockerconfigjson "$PAYLOADIMAGE" | grep hypershift | awk '{print $2}')}"
echo "${HO_OPERATOR_IMAGE}" > /home/ho_operator_image
###


if [[ -z ${MCE} ]] ; then
  ### workaround for https://issues.redhat.com/browse/OCPBUGS-32770
  echo "workaround for https://issues.redhat.com/browse/OCPBUGS-32770"
  CNV_PRERELEASE_VERSION=$(cat /home/cnv-prerelease-version)
  jq -s '.[0] * .[1]' /home/pull-secret /tmp/.dockerconfigjson > /home/pull-secret-mirror
  oc image -a /home/pull-secret-mirror mirror registry.ci.openshift.org/ocp/${CNV_PRERELEASE_VERSION}:cluster-api-provider-kubevirt ${mirror_registry}/${LOCALIMAGES}/${CNV_PRERELEASE_VERSION}:cluster-api-provider-kubevirt
  echo "${mirror_registry}/${LOCALIMAGES}/${CNV_PRERELEASE_VERSION}:cluster-api-provider-kubevirt" > /home/capi_provider_kubevirt_image
  ###

  ### workaround for https://issues.redhat.com/browse/OCPBUGS-32765
  echo "workaround for https://issues.redhat.com/browse/OCPBUGS-32765"
  # please remember to keep it consistent when the image reference on
  # https://github.com/openshift/hypershift/blob/94092458fd77a0ae7f5d5126aa45fc03f9b74323/cmd/install/install.go#L51-L55
  # gets bumped
  oc image mirror --keep-manifest-list=true registry.redhat.io/edo/external-dns-rhel8@sha256:638fb6b5fc348f5cf52b9800d3d8e9f5315078fc9b1e57e800cb0a4a50f1b4b9 ${mirror_registry}/${LOCALIMAGES}/external-dns-rhel8
  oc apply -f - <<EOF2
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: external-dns-rhel8
spec:
  imageDigestMirrors:
  - mirrors:
    - ${mirror_registry}/${LOCALIMAGES}/external-dns-rhel8
    source: registry.redhat.io/edo/external-dns-rhel8
EOF2
  sleep 180
  oc delete pods -n hypershift -l=name=external-dns
  ###
fi


EOF

scp "${SSHOPTS[@]}" "root@${IP}:/home/ho_operator_image" "${SHARED_DIR}/ho_operator_image"
### workaround for https://issues.redhat.com/browse/CNV-38194
echo "workaround for https://issues.redhat.com/browse/CNV-38194"
scp "${SSHOPTS[@]}" "root@${IP}:/etc/pki/ca-trust/source/anchors/registry.2.crt" "${SHARED_DIR}/registry.2.crt"
###

### workaround for https://issues.redhat.com/browse/OCPBUGS-32770
if [[ -z ${MCE} ]] ; then
  echo "workaround for https://issues.redhat.com/browse/OCPBUGS-32770"
  scp "${SSHOPTS[@]}" "root@${IP}:/home/capi_provider_kubevirt_image" "${SHARED_DIR}/capi_provider_kubevirt_image"
fi
###

###
# For some reason operator-ose-csi-external-snapshotter-rhel8 is not correctly appearing
# in the ICSP/IDMS generated by oc-mirror, let's explicitly add it
# TODO: investigate why and eventually file a bug
oc apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: operator-ose-csi-external-snapshotter-rhel8
spec:
  imageDigestMirrors:
  - mirrors:
    - virthost.ostest.test.metalkube.org:5000/openshift4/ose-csi-external-snapshotter-rhel8
    source: registry.redhat.io/openshift4/ose-csi-external-snapshotter-rhel8
EOF
sleep 120
oc delete pods -n openshift-storage -l=app=csi-rbdplugin-provisioner
oc delete pods -n openshift-storage -l=app=csi-cephfsplugin-provisioner
###