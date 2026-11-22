#!/usr/bin/env bash
# Refleja imágenes de plataforma a ECR privado una vez que Terraform haya
# creado sus repositorios. No se invoca desde CI/CD ni crea repositorios: está
# diseñado para una estación aprobada con Internet y credenciales temporales.
set -euo pipefail

: "${AWS_REGION:?AWS_REGION es obligatorio}"
: "${ARGO_ROLLOUTS_SOURCE_IMAGE:?Indique una imagen de Argo Rollouts compatible y fijada por digest}"
: "${AWS_LOAD_BALANCER_CONTROLLER_SOURCE_IMAGE:?Indique una imagen de AWS Load Balancer Controller compatible y fijada por digest}"

for command in aws docker jq; do
  command -v "$command" >/dev/null || { echo "Falta $command" >&2; exit 69; }
done

fluent_bit_source="${FLUENT_BIT_SOURCE_IMAGE:-public.ecr.aws/aws-observability/aws-for-fluent-bit:2.32.4}"
registry="$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com"
output_file="${PLATFORM_IMAGES_FILE:-platform-images.json}"

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$registry"
images='{}'

mirror() {
  local component="$1"
  local source_image="$2"
  local target_image="$registry/aegisvolt/$component"

  docker pull "$source_image"
  docker tag "$source_image" "$target_image:mirror"
  docker push "$target_image:mirror"
  local digest
  digest="$(aws ecr describe-images --region "$AWS_REGION" --repository-name "aegisvolt/$component" --image-ids imageTag=mirror --query 'imageDetails[0].imageDigest' --output text)"
  images="$(jq --arg component "$component" --arg image "$target_image@$digest" '. + {($component): $image}' <<<"$images")"
}

mirror "aws-for-fluent-bit" "$fluent_bit_source"
mirror "argo-rollouts" "$ARGO_ROLLOUTS_SOURCE_IMAGE"
mirror "aws-load-balancer-controller" "$AWS_LOAD_BALANCER_CONTROLLER_SOURCE_IMAGE"

jq -e 'length == 3 and all(.[]; type == "string" and test("@sha256:[0-9a-f]{64}$"))' <<<"$images" >/dev/null
printf '%s\n' "$images" > "$output_file"
printf '%s\n' "$images"
