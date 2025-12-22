-- Resident Evil 2 DX11 camera export for gcv_reshade
-- 与原版 residentevil_read_camera_matrix_transfcoords.lua 一致，仅修改触发魔数

if reframework:get_game_name() ~= "re2" then
    return
end

MyCamCoordsStash = {
    counter = -1.5,
    -- 这里的 1.200405... 必须与 ResidentEvil2::get_scriptedcambuf_triggerbytes 中的 magic_double 一致
    contiguousmembuf = { 1.20040525131452021e-12, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 },
}

local function zero_the_cambuf()
    for i=3,15 do
        MyCamCoordsStash.contiguousmembuf[i] = 0;
    end
    -- 保持 hash 有效，便于扫描
    MyCamCoordsStash.contiguousmembuf[16] = MyCamCoordsStash.contiguousmembuf[2];
    MyCamCoordsStash.contiguousmembuf[17] = MyCamCoordsStash.contiguousmembuf[2];
end

re.on_application_entry("BeginRendering", function()
    if MyCamCoordsStash.counter < 0.0 then
        MyCamCoordsStash.counter = 2.0;
    else
        MyCamCoordsStash.counter = MyCamCoordsStash.counter + 1.0;
        if MyCamCoordsStash.counter > 9999.5 then
            MyCamCoordsStash.counter = 1.0;
        end
    end

    local gamecam = sdk.get_primary_camera();
    if gamecam ~= nil then
        local exm = gamecam:call("get_WorldMatrix");
        local fovmat = gamecam:call("get_ProjectionMatrix");
        if exm ~= nil and fovmat ~= nil then
            -- exm[j] 是 cam2world 的第 j 列，下面这组变换是作者为了统一各游戏坐标系做的旋转
            local fovhdeg = math.atan(1.0/(fovmat[0].x))*(360.0/math.pi);
            local poshash1 = (MyCamCoordsStash.counter + exm[0].x - exm[2].x + exm[1].x + exm[3].x
                - exm[0].z + exm[2].z - exm[1].z - exm[3].z
                + exm[0].y - exm[2].y + exm[1].y + exm[3].y + fovhdeg);
            local poshash2 = (MyCamCoordsStash.counter - exm[0].x - exm[2].x - exm[1].x + exm[3].x
                + exm[0].z + exm[2].z + exm[1].z - exm[3].z
                - exm[0].y - exm[2].y - exm[1].y + exm[3].y - fovhdeg);

            MyCamCoordsStash.contiguousmembuf[ 2] = MyCamCoordsStash.counter;
            MyCamCoordsStash.contiguousmembuf[ 3] = exm[0].x;
            MyCamCoordsStash.contiguousmembuf[ 4] = -exm[2].x;
            MyCamCoordsStash.contiguousmembuf[ 5] = exm[1].x;
            MyCamCoordsStash.contiguousmembuf[ 6] = exm[3].x;
            MyCamCoordsStash.contiguousmembuf[ 7] = -exm[0].z;
            MyCamCoordsStash.contiguousmembuf[ 8] = exm[2].z;
            MyCamCoordsStash.contiguousmembuf[ 9] = -exm[1].z;
            MyCamCoordsStash.contiguousmembuf[10] = -exm[3].z;
            MyCamCoordsStash.contiguousmembuf[11] = exm[0].y;
            MyCamCoordsStash.contiguousmembuf[12] = -exm[2].y;
            MyCamCoordsStash.contiguousmembuf[13] = exm[1].y;
            MyCamCoordsStash.contiguousmembuf[14] = exm[3].y;
            MyCamCoordsStash.contiguousmembuf[15] = fovhdeg;
            MyCamCoordsStash.contiguousmembuf[16] = poshash1;
            MyCamCoordsStash.contiguousmembuf[17] = poshash2;
        else
            zero_the_cambuf();
        end
    else
        zero_the_cambuf();
    end
end)
