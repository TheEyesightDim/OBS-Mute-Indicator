--obslua = {} --comment this line out in the release plugin. It's just to kill diagnostics errors due to undefined symbols.
obs = obslua

g_audio_source = nil
g_graphics_source = nil

--[[ SECTION: Functions exported to OBS ]]--

function script_description()
    return "Sets the visibility of a source based on the mute status of an audio input."
end

function script_properties()
    local props = obs.obs_properties_create()
    
    --an audio mixer input
    local p_list_audio_sources = obs.obs_properties_add_list(props, "audio_source", "Audio Input Source", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local audio_sources = list_audio_source_names()
    for _, name in pairs(audio_sources) do
        obs.obs_property_list_add_string(p_list_audio_sources, name, name)
    end
    --a scene source to control
    local p_list_graphics_sources = obs.obs_properties_add_list(props, "graphics_source", "Source to control", obs.OBS_COMBO_TYPE_EDITABLE, obs.OBS_COMBO_FORMAT_STRING)
    local graphics_sources = list_graphics_source_names()
    for _, name in pairs(graphics_sources) do
        obs.obs_property_list_add_string(p_list_graphics_sources, name, name)
    end

    return props
end

function script_update(settings)
    -- clear the callback on the audio source first incase our source has changed
    clear_mute_callback(g_audio_source)

    g_audio_source = obs.obs_data_get_string(settings, "audio_source")
    g_graphics_source = obs.obs_data_get_string(settings, "graphics_source")
    print("INFO: Audio source is ".. g_audio_source)
    print("INFO: Graphics source is ".. g_graphics_source)

    set_mute_callback(g_audio_source)
end

function script_load(settings)
end

-- It doesn't make sense to pick default selections from the many scene sources,
-- So leave this empty.
function script_defaults(settings)
end


--[[ SECTION: Functions for internal use by this module only ]]--

--returns a list of the strings of names of OBS graphical sources (sources which can have their visibility toggled)
function list_graphics_source_names()
    -- obs_source_info.type: OBS_SOURCE_TYPE_INPUT &&  obs_source_info.output_flags: OBS_SOURCE_VIDEO
    local sources = obs.obs_enum_sources()
    local graphics_sources = {}

    -- Iterate through the sources and add them if they are an input type and have the audio source capability flag
    for i, source in pairs(sources) do 
        if obs.obs_source_get_type(source) == obs.OBS_SOURCE_TYPE_INPUT then
            local capability_flags = obs.obs_source_get_output_flags(source)
            if bit_test(capability_flags, obs.OBS_SOURCE_VIDEO) then
                local str_source_name = obs.obs_source_get_name(source)
                table.insert(graphics_sources, str_source_name)
            end
        end
    end
    
    obs.source_list_release(sources)
    return graphics_sources
end

--returns a list of the strings of names of OBS audio sources
function list_audio_source_names()
    local sources = obs.obs_enum_sources()
    local audio_sources = {}

    -- Iterate through the sources and add them if they are an input type and have the audio source capability flag
    for i, source in pairs(sources) do 
        if obs.obs_source_get_type(source) == obs.OBS_SOURCE_TYPE_INPUT then
            local capability_flags = obs.obs_source_get_output_flags(source)
            if bit_test(capability_flags, obs.OBS_SOURCE_AUDIO) then
                local str_source_name = obs.obs_source_get_name(source)
                table.insert(audio_sources, str_source_name)
            end
        end
    end

    obs.source_list_release(sources)
    return audio_sources
end

function set_mute_callback(source_name)
    if not g_audio_source then
        print("WARNING: Tried to set callback when g_audio_source was Nil.")
        return
    end

    local source = obs.obs_get_source_by_name(source_name)
    if not source then
        print("ERROR: Couldn't set callback on source ".. source_name)
        return
    end

    local handler = obs.obs_source_get_signal_handler(source)
    obs.signal_handler_connect(handler, "mute", cb_audio_mute_change)
    print("INFO: Callback set for ".. source_name)

    obs.obs_source_release(source)
end

function clear_mute_callback(source_name)
    if not g_audio_source then
        print("WARNING: Tried to clear callback when g_audio_source was Nil.")
        return
    end

    local source = obs.obs_get_source_by_name(source_name)
    if not source then
        print("ERROR: Couldn't remove callback on source ".. source_name)
        return
    end

    local handler = obs.obs_source_get_signal_handler(source)
    obs.signal_handler_disconnect(handler, "mute", cb_audio_mute_change)
    print("INFO: Callback cleared for ".. source_name)

    obs.obs_source_release(source)
end



function set_source_enabled_state(source_name, b_enabled)
    --https://obsproject.com/docs/reference-core.html?highlight=get_source_by_name#c.obs_get_source_by_name
    --https://obsproject.com/docs/reference-sources.html?highlight=activate#c.obs_source_enabled

    -- Acquired sources must be manually released!
    local source = obs.obs_get_source_by_name(source_name)
    obs.obs_source_set_enabled(source, b_enabled)

    -- Manually release the acquired source!
    obs.obs_source_release(source)
end

-- This is the callback that will trigger on audio mute state change,
-- and will call `set_source_enabled_state(...)` to toggle a source's visibility.
function cb_audio_mute_change(calldata_t)
    local audio_source = obs.obs_get_source_by_name(g_audio_source)
    local graphics_source = obs.obs_get_source_by_name(g_graphics_source)

    if obs.calldata_bool(calldata_t, "muted") then
        set_source_enabled_state(g_graphics_source, true)
    else
        set_source_enabled_state(g_graphics_source, false)
    end

    obs.obs_source_release(audio_source)
    obs.obs_source_release(graphics_source)
end

-- Lua 5.1 workaround for lack of bitwise operator &.
--
-- Returns true if all the bits in `q` are also set in `p`.
--
-- Only defined for integer `p` and `q` in the range of [0..2^32).
-- The fractional part will be ignored.
function bit_test(p, q)
    local a, b = p, q
    local bits_a, bits_b = {}, {}

    for i = 31, 0, -1 do
        a = a - 2^i
        if a >= 0 then
            table.insert(bits_a, true)
        else
            table.insert(bits_a, false)
            a = a + 2^i
        end
    end

    for i = 31, 0, -1 do
        b = b - 2^i
        if b >= 0 then
            table.insert(bits_b, true)
        else
            table.insert(bits_b, false)
            b = b + 2^i
        end
    end

    for i = 1, 32 do
        if bits_b[i] and (not bits_a[i]) then
            return false
        end
    end

    return true
end
