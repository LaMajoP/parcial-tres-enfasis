# Imagen multi-stage común; cada componente se selecciona con el comando de Compose/Kubernetes.
FROM node:24.19.0-alpine AS dependencies
WORKDIR /workspace
COPY package.json ./
COPY apps/graphql-gateway/package.json apps/graphql-gateway/package.json
COPY apps/web/package.json apps/web/package.json
COPY services/station-reservation-service/package.json services/station-reservation-service/package.json
COPY services/billing-wallet-service/package.json services/billing-wallet-service/package.json
COPY services/energy-dispatch-service/package.json services/energy-dispatch-service/package.json
COPY packages/contracts/package.json packages/contracts/package.json
COPY packages/shared-observability/package.json packages/shared-observability/package.json
COPY packages/shared-test-utils/package.json packages/shared-test-utils/package.json
RUN npm install --ignore-scripts --no-audit --no-fund

FROM dependencies AS build
COPY . .
RUN npm run build

FROM node:24.19.0-alpine AS runtime
WORKDIR /workspace
ENV NODE_ENV=production
COPY --from=dependencies /workspace/node_modules ./node_modules
COPY --from=build /workspace/apps ./apps
COPY --from=build /workspace/services ./services
COPY --from=build /workspace/packages ./packages
COPY --from=build /workspace/scripts ./scripts
COPY --from=build /workspace/package.json ./package.json
USER node
CMD ["node", "--import", "tsx", "apps/graphql-gateway/src/index.ts"]
