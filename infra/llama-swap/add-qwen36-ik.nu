#!/usr/bin/env nu
# Prepare the Qwen3.6 ik route and Pi entry. --apply validates and installs them.
def main [
    --config: string = '/home/yurko/Code/piano/infra/llama-swap/config.yaml'
    --pi-models: string = '/home/yurko/.pi/agent/models.json'
    --output: string
    --apply
] {
    let spec = (open ($env.FILE_PWD | path join 'qwen36-ik.json'))
    let config_before = (open $config)
    let pi_before = (open $pi_models)
    if $config_before.routing.router.use != 'matrix' {
        error make {msg: 'This profile requires the current llama-swap matrix router.'}
    }
    let route_models = ($config_before.models | upsert $spec.id $spec.route)
    let config_after = ($config_before | upsert models $route_models
        | upsert routing.router.settings.matrix.vars.qwen36ik $spec.id
        | upsert routing.router.settings.matrix.sets.qwen36ik_only 'qwen36ik')
    let pi_list = ($pi_before.providers.llama_swap.models | where id != $spec.id | append $spec.piModel)
    let pi_after = ($pi_before | upsert providers.llama_swap.models $pi_list)
    let out = if $output == null {
        '/home/yurko/llm/maintenance/route-updates' | path join (date now | format date '%Y%m%dT%H%M%S%f')
    } else { $output | path expand }
    mkdir $out
    ^chmod 700 $out
    if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Cannot secure staging directory'} }
    cp $config ($out | path join 'config.before.yaml')
    cp $pi_models ($out | path join 'pi.before.json')
    $config_after | to yaml | save --force ($out | path join 'config.yaml')
    $pi_after | to json --indent 2 | save --force ($out | path join 'pi.json')
    ^chmod 600 ($out | path join 'pi.json')
    if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Cannot secure staged Pi configuration'} }
    if $apply {
        ^docker cp ($out | path join 'config.yaml') 'piano-llama-swap:/tmp/qwen36-ik-candidate.yaml'
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Cannot stage config in container'} }
        ^docker exec piano-llama-swap llama-swap --config /tmp/qwen36-ik-candidate.yaml --validate
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Config validation failed; live files unchanged'} }
        # Keep the bind-mounted file inode so watch-config sees the new content.
        open --raw ($out | path join 'config.yaml') | save --force $config
        open --raw ($out | path join 'pi.json') | save --force $pi_models
    }
    print $"Prepared ($spec.id); applied=($apply); backups and candidates: ($out)"
}
