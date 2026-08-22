# Stage 1: base — enable pnpm
FROM node:22-alpine AS base
ENV COREPACK_ENABLE_AUTO_PIN=0
RUN corepack enable && corepack prepare pnpm@10.25.0 --activate
WORKDIR /app

# Stage 2: build — full build with native deps (bcrypt) + Prisma generate
FROM base AS build
RUN apk add --no-cache python3 make g++
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY prisma ./prisma/
RUN pnpm exec prisma generate
COPY . .
RUN pnpm build
# Prune dev dependencies in place, keeping Prisma client intact
RUN pnpm prune --prod

# Stage 3: runner — minimal production image
FROM base AS runner
# yt-dlp + ffmpeg are required by the BoardModule to resolve Instagram/TikTok
# URLs into raw video files before TwelveLabs analysis.
# yt-dlp is installed from PyPI's NIGHTLY channel (--pre), not Alpine's apk
# package: TikTok/Instagram break yt-dlp's extractors frequently and the apk
# package tracks stable, which lags weeks behind (e.g. the "Unable to extract
# universal data for rehydration" TikTok breakage). The standalone Linux binary
# is a glibc PyInstaller build and won't run on musl, so pip is the only path.
RUN apk add --no-cache python3 py3-pip ffmpeg \
    && pip install --break-system-packages --no-cache-dir -U --pre "yt-dlp[default]" \
    # gallery-dl handles TikTok photo (image carousel) posts, which yt-dlp
    # wontfix'd. Installed separately so it tracks stable releases — the
    # --pre nightly channel above is a yt-dlp-specific need.
    && pip install --break-system-packages --no-cache-dir gallery-dl
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/keys ./keys
COPY --from=build /app/certs ./certs
COPY --from=build /app/pnpm-lock.yaml ./
COPY package.json ./
ARG COMMIT_SHA=""
ENV SERVER_COMMIT_SHA=${COMMIT_SHA}
USER node
EXPOSE 3000
CMD ["node", "dist/src/main"]
