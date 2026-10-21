#!/usr/bin/env bash
set -euo pipefail
: "${TCR_USERNAME:?configure TCR_DEPLOY_USERNAME}"
: "${TCR_PASSWORD:?configure TCR_DEPLOY_PASSWORD}"
: "${DELIVERY_TOKEN:?configure GIT_ACTION_BOT with app-delivery write access}"
: "${GITHUB_SHA:?}"
: "${GITHUB_RUN_ID:?}"
: "${GITHUB_RUN_ATTEMPT:?}"
[[ "${GITHUB_REPOSITORY:-}" == pingkaicloud/CloudRec ]]
[[ "${GITHUB_REF_NAME:-}" == "cloudsec-dev-image-${GITHUB_SHA}" ]]
registry=clinic.tencentcloudcr.com
base="$registry/clinic-dev"
tag="dev-${GITHUB_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
tmp="$(mktemp -d)"
export DOCKER_CONFIG="$tmp/docker"
mkdir -p "$DOCKER_CONFIG"
trap 'rm -rf "$tmp"' EXIT
printf '%s' "$TCR_PASSWORD" | docker login "$registry" -u "$TCR_USERNAME" --password-stdin
for component in cloudrec cloudrec-mysql; do
  if [[ "$component" == cloudrec ]]; then
    source="cloudrec-test:$GITHUB_SHA"
  else
    source=mysql:8.0.40
    docker pull --platform linux/amd64 "$source"
  fi
  target="$base/$component:$tag"
  docker tag "$source" "$target"
  docker push "$target"
  docker pull "$target"
  digest="$(docker inspect --format '{{index .RepoDigests 0}}' "$target")"
  [[ "$digest" =~ @sha256:[0-9a-f]{64}$ ]] || { echo 'registry digest missing' >&2; exit 1; }
  printf '%s\n' "$digest" > "$tmp/$component.digest"
done
# Scope authentication to this process; never persist the token in the remote URL.
auth="$(printf 'x-access-token:%s' "$DELIVERY_TOKEN" | base64 | tr -d '\n')"
echo "::add-mask::$auth"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth"
git clone --single-branch --branch shaotao/cloudsec https://github.com/pingkaicloud/app-delivery.git "$tmp/delivery"
cd "$tmp/delivery"
python3 cloudsec/scripts/update-images.py \
  "$(cat "$tmp/cloudrec.digest")" "$(cat "$tmp/cloudrec-mysql.digest")" "$GITHUB_SHA"
git config user.name 'PingKai CloudSec CD'
git config user.email 'cloudsec-cd@users.noreply.github.com'
git add cloudsec/envs/tke-dev/kustomization.yaml cloudsec/release.json
git commit -m "build(cloudsec): publish DEV ${GITHUB_SHA:0:12}"
git push origin HEAD:refs/heads/shaotao/cloudsec
release="cloudsec-dev-cd-$(date -u +%Y%m%d%H%M%S)-$(git rev-parse --short=7 HEAD)"
git tag -a "$release" -m "CloudRec DEV source $GITHUB_SHA; images $tag"
git push origin "refs/tags/$release"
printf 'App Delivery tag: %s\nSource: %s\n' "$release" "$GITHUB_SHA" >> "$GITHUB_STEP_SUMMARY"
# Poll the actual downstream tag workflow; an image push alone is not deployment proof.
export CLOUDSEC_RELEASE_TAG="$release"
python3 - <<'PY'
import json, os, time, urllib.request
base = 'https://api.github.com/repos/pingkaicloud/app-delivery/actions/runs?event=push&per_page=100'
headers = {'Authorization': 'Bearer '+os.environ['DELIVERY_TOKEN'], 'Accept':'application/vnd.github+json'}
tag = os.environ['CLOUDSEC_RELEASE_TAG']
for _ in range(180):
    with urllib.request.urlopen(urllib.request.Request(base, headers=headers), timeout=30) as r:
        runs=json.load(r)['workflow_runs']
    matching=[r for r in runs if r['head_branch']==tag and r.get('path')=='.github/workflows/cloudsec-tke-cd.yml']
    if matching:
        run=matching[0]
        if run['status']=='completed':
            print('Downstream deployment:',run['html_url'],run['conclusion'])
            if run['conclusion']!='success': raise SystemExit(1)
            break
    time.sleep(10)
else:
    raise SystemExit('Downstream deployment did not finish within 30 minutes; inspect Actions')
PY
