#!/usr/bin/env bash
# Requiere credenciales AWS ya configuradas. Construye una vez el commit de dev
# y escribe un objeto JSON con referencias ECR inmutables por digest.
set -euo pipefail

: "${AWS_REGION:?AWS_REGION es obligatorio}"
: "${IMAGE_TAG:?IMAGE_TAG es obligatorio}"
output_file="${PROMOTED_IMAGES_FILE:-promoted-images.json}"
test -f package-lock.json || { echo "Falta package-lock.json" >&2; exit 65; }

registry="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password | docker login --username AWS --password-stdin "$registry"
for component in graphql-gateway station-reservation billing-wallet energy-dispatch; do
  docker build --target runtime -t "$registry/aegisvolt/$component:$IMAGE_TAG" .
  docker push "$registry/aegisvolt/$component:$IMAGE_TAG"
done
docker build --target web-runtime -t "$registry/aegisvolt/web:$IMAGE_TAG" .
docker push "$registry/aegisvolt/web:$IMAGE_TAG"

images='{}'
for component in graphql-gateway station-reservation billing-wallet energy-dispatch web; do
  digest="$(aws ecr describe-images --repository-name "aegisvolt/$component" --image-ids imageTag="$IMAGE_TAG" --query 'imageDetails[0].imageDigest' --output text)"
  images="$(jq --arg component "$component" --arg image "$registry/aegisvolt/$component@$digest" '. + {($component): $image}' <<<"$images")"
done
jq -e 'length == 5 and all(.[]; test("@sha256:[0-9a-f]{64}$"))' <<<"$images" >/dev/null
printf '%s\n' "$images" > "$output_file"
printf '%s\n' "$images"
