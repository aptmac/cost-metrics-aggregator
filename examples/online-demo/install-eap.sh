#!/bin/bash

NAMESPACE="eap"

oc new-project $NAMESPACE 2>/dev/null || oc project $NAMESPACE

helm repo add jboss-eap https://jbossas.github.io/eap-charts/ 2>/dev/null || true
helm install eap8-app jboss-eap/eap8
