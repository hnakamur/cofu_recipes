include_recipe "lib/lxd_container.lua"

-- functional style call examples of lxd_container

local container_name = string.format("my-tmp-ubuntu-%s", os.date("%Y-%m-%d-%H-%M-%S"))

lxd_container(container_name, {
    image = "images:ubuntu/xenial/amd64"
})

lxd_container(container_name, {
    state = "absent",
    force_delete = true
})


-- domain specific language style call examples of lxd_container

lxd_container "tmp-ubuntu-created-by-cofu-example" {
    image = "images:ubuntu/xenial/amd64"
}

lxd_container "tmp-ubuntu-created-by-cofu-example" {
    state = "absent",
    force_delete = true
}
