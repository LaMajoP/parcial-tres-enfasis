# Imagen multi-stage común; cada componente se selecciona con el comando de Compose/Kubernetes.
FROM node:24.19.0-alpine AS dependencies
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY apps/graphql-gateway/package.json apps/graphql-gateway/package.json
COPY apps/web/package.json apps/web/package.json
COPY services/station-reservation-service/package.json services/station-reservation-service/package.json
COPY services/billing-wallet-service/package.json services/billing-wallet-service/package.json
COPY services/energy-dispatch-service/package.json services/energy-dispatch-service/package.json
COPY packages/contracts/package.json packages/contracts/package.json
COPY packages/shared-observability/package.json packages/shared-observability/package.json
COPY packages/shared-test-utils/package.json packages/shared-test-utils/package.json
RUN npm ci --ignore-scripts --no-audit --no-fund

FROM dependencies AS build
COPY . .
ARG VITE_GRAPHQL_URL=/graphql
ENV VITE_GRAPHQL_URL=$VITE_GRAPHQL_URL
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
USER 1000:1000
CMD ["node", "--import", "tsx", "apps/graphql-gateway/src/index.ts"]

# La UI se distribuye como estáticos; no se ejecuta Vite de desarrollo en EKS.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS web-runtime
COPY --from=build /workspace/apps/web/dist /usr/share/nginx/html
EXPOSE 8080

# Solo para demo de rollback: health permanece lista, pero /graphql devuelve
# 500 para que AnalysisRun mida una regresión real de negocio.
FROM runtime AS gateway-defective
ENV DEMO_CANARY_FORCE_ERROR=true
