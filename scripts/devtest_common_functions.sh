#!/bin/bash
#
# Functions common for devtest_* scripts

function set_keystone_certs() {
    local cert_var="${1}_CERT_DIR"
    local cert_dir=${!cert_var-''}
    local delete_cert_dir=0

    if [ -z "$cert_dir" ]; then
        delete_cert_dir=1
        cert_dir=$(mktemp -d --tmpdir cert.XXXXXXXX)
        generate-keystone-pki $cert_dir
    fi

    CA_CERT=$(<$cert_dir/ca_cert.pem)
    SIGNING_KEY=$(<$cert_dir/signing_key.pem)
    SIGNING_CERT=$(<$cert_dir/signing_cert.pem)

    if [ "$delete_cert_dir" = 1 ]; then
        rm -rf $cert_dir
    fi
}
