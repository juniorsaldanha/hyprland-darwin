#!/usr/bin/env bash
# Shell completion for the `hypr` CLI, from grammar/commands-bnf-grammar.txt, into .shell-completion/
cd "$(dirname "$0")"
source ./script/setup.sh

./script/install-dep.sh --complgen

rm -rf .shell-completion && mkdir -p \
    .shell-completion/zsh \
    .shell-completion/fish \
    .shell-completion/bash

./.deps/cargo-root/bin/complgen aot ./grammar/commands-bnf-grammar.txt \
    --zsh-script .shell-completion/zsh/_hypr \
    --fish-script .shell-completion/fish/hypr.fish \
    --bash-script .shell-completion/bash/hypr

# Check basic syntax (fish only when it's installed: CI runners don't have it)
zsh -c 'autoload -Uz compinit; compinit; source ./.shell-completion/zsh/_hypr'
if command -v fish > /dev/null; then fish -c 'source ./.shell-completion/fish/hypr.fish'; fi
bash -c 'source ./.shell-completion/bash/hypr'
