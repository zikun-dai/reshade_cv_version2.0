-- Resident Evil 2 DX11 camera export for gcv_reshade
if reframework:get_game_name() ~= "re2" then
    return
end

local MAGIC = 1.20040525131452021e-12
local COUNTER_MIN, COUNTER_MAX = 2.0, 9999.0

local function make_buffer()
    return {
        MAGIC,  -- trigger value searched by gcv_reshade
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0, 0, 0,
        0, 0,        -- fov placeholder
        0, 0         -- hashes
    }
end

MyCamCoordsStash = MyCamCoordsStash or { counter = -1.0 }
MyCamCoordsStash.contiguousmembuf = MyCamCoordsStash.contiguousmembuf or make_buffer()
local stash = MyCamCoordsStash
local buf = stash.contiguousmembuf
buf[1] = MAGIC

local function reset_buffer()
    buf[2] = stash.counter
    for i = 3, 15 do
        buf[i] = 0.0
    end
    buf[16] = buf[2]
    buf[17] = buf[2]
end

local function recompute_hashes()
    local sum = buf[2]
    local alt = buf[2]
    for i = 3, 15 do
        local idx = i - 2
        local value = buf[i]
        sum = sum + value
        if idx % 2 == 0 then
            alt = alt + value
        else
            alt = alt - value
        end
    end
    buf[16] = sum
    buf[17] = alt
end

local function write_camera(camera)
    local world = camera:call("get_WorldMatrix")
    local proj = camera:call("get_ProjectionMatrix")
    if not world or not proj then
        reset_buffer()
        return
    end

    buf[2] = stash.counter
    -- row 0
    buf[3] = world[0].x
    buf[4] = -world[2].x
    buf[5] = world[1].x
    buf[6] = world[3].x
    -- row 1
    buf[7]  = -world[0].z
    buf[8]  = world[2].z
    buf[9]  = -world[1].z
    buf[10] = -world[3].z
    -- row 2
    buf[11] = world[0].y
    buf[12] = -world[2].y
    buf[13] = world[1].y
    buf[14] = world[3].y

    buf[15] = math.atan(1.0 / proj[0].x) * (360.0 / math.pi) -- horizontal FOV in degrees
    recompute_hashes()
end

re.on_application_entry("BeginRendering", function()
    if stash.counter < 0 then
        stash.counter = COUNTER_MIN
    else
        stash.counter = stash.counter + 1.0
        if stash.counter > COUNTER_MAX then
            stash.counter = 1.0
        end
    end

    local camera = sdk.get_primary_camera()
    if camera then
        write_camera(camera)
        local b = MyCamCoordsStash.contiguousmembuf
        log.info(string.format("LUA_CAM: %.6f %.6f %.6f %.6f  %.6f %.6f %.6f %.6f  %.6f %.6f %.6f %.6f  FOV=%.6f",
            b[3], b[4], b[5],  b[6],
            b[7], b[8], b[9],  b[10],
            b[11], b[12], b[13], b[14],
            b[15]))
    else
        reset_buffer()
    end
end)
