require("premake", ">=5.0.0-beta2")

-- don't forget to set env var CMAKE_GENERATOR to one of these values:
-- https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html#manual:cmake-generators(7)
-- common ones
-- ============
-- Unix Makefiles
-- Visual Studio 17 2022
-- MSYS Makefiles

local os_iden = '' -- identifier
if os.target() == "windows" then
    os_iden = 'win'
elseif os.target() == "linux" then
    os_iden = 'linux'
else
    error('Unsupported os target: "' .. os.target() .. '"')
end


-- options
---------
-- general
newoption {
    category = "general",
    trigger = "verbose",
    description = "Verbose output",
}
newoption {
    category = "general",
    trigger = "clean",
    description = "Cleanup before any action",
}

-- local tools
newoption {
    category = "tools",
    trigger = "custom-cmake",
    description = "Use custom cmake",
    value = 'path/to/cmake.exe',
    default = nil
}

-- deps extraction
newoption {
    category = "extract",
    trigger = "all-ext",
    description = "Extract all deps",
}

newoption {
    category = "extract",
    trigger = "ext-ssq",
    description = "Extract ssq",
}
newoption {
    category = "extract",
    trigger = "ext-zlib",
    description = "Extract zlib",
}
newoption {
    category = "extract",
    trigger = "ext-curl",
    description = "Extract curl",
}
newoption {
    category = "extract",
    trigger = "ext-protobuf",
    description = "Extract protobuf",
}
newoption {
    category = "extract",
    trigger = "ext-mbedtls",
    description = "Extract mbedtls",
}
newoption {
    category = "extract",
    trigger = "ext-ingame_overlay",
    description = "Extract ingame_overlay",
}

-- build
newoption {
    category = "build",
    trigger = "all-build",
    description = "Build all deps",
}
newoption {
    category = "build",
    trigger = "32-build",
    description = "Build for 32-bit arch",
}
newoption {
    category = "build",
    trigger = "64-build",
    description = "Build for 64-bit arch",
}

newoption {
    category = "build",
    trigger = "build-ssq",
    description = "Build ssq",
}
newoption {
    category = "build",
    trigger = "build-zlib",
    description = "Build zlib",
}
newoption {
    category = "build",
    trigger = "build-curl",
    description = "Build curl",
}
newoption {
    category = "build",
    trigger = "build-protobuf",
    description = "Build protobuf",
}
newoption {
    category = "build",
    trigger = "build-mbedtls",
    description = "Build mbedtls",
}
newoption {
    category = "build",
    trigger = "build-ingame_overlay",
    description = "Build ingame_overlay",
}


local function merge_list(src, dest)
    local src_count = #src
    local res = {}

    for idx = 1, src_count do
        res[idx] = src[idx]
    end

    for idx = 1, #dest do
        res[src_count + idx] = dest[idx]
    end
    return res
end



-- common defs
---------
local deps_dir = path.getabsolute(path.join('build', 'deps', os_iden), _MAIN_SCRIPT_DIR)
local third_party_dir = path.getabsolute('third-party')
local third_party_deps_dir = path.join(third_party_dir, 'deps', os_iden)
local third_party_common_dir = path.join(third_party_dir, 'deps', 'common')
local extractor = os.realpath(path.join(third_party_deps_dir, '7za', '7za'))
local mycmake = os.realpath(path.join(third_party_deps_dir, 'cmake', 'bin', 'cmake'))

if _OPTIONS["custom-cmake"] then
    mycmake = _OPTIONS["custom-cmake"]
    print('using custom cmake: ' .. _OPTIONS["custom-cmake"])
else
    if os.host() == 'windows' then
        mycmake = mycmake .. '.exe'
    end
    if not os.isfile(mycmake) then
        error('cmake is missing from third-party dir, you can specify custom cmake location, run the script with --help. cmake: ' .. mycmake)
    end
end

if not third_party_dir or not os.isdir(third_party_dir) then
    error('third-party dir is missing')
end

if os.host() == 'windows' then
    extractor = extractor .. '.exe'
end
if not extractor or not os.isfile(extractor) then
    error('extractor is missing from third-party dir. extractor: ' .. extractor)
end


-- ############## common CMAKE args ##############
-- https://cmake.org/cmake/help/latest/variable/CMAKE_LANG_FLAGS_CONFIG.html#variable:CMAKE_%3CLANG%3E_FLAGS_%3CCONFIG%3E
local cmake_common_defs = {
    'CMAKE_BUILD_TYPE=Release',
    'CMAKE_POSITION_INDEPENDENT_CODE=True',
    'BUILD_SHARED_LIBS=OFF',
}
if os.target() == 'windows' and string.match(_ACTION, 'vs.+') then
    table.insert(cmake_common_defs, 'CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded')
end


local function cmake_build(dep_folder, is_32, extra_cmd_defs, c_flags_init, cxx_flags_init)
    local dep_base = path.getabsolute(path.join(deps_dir, dep_folder))
    local arch_iden = ''
    if is_32 then
        arch_iden = '32'
    else
        arch_iden = '64'
    end

    print('\n\nbuilding dep: "' .. dep_base .. '"')
    
    local build_dir = path.getabsolute(path.join(dep_base, 'build' .. arch_iden))
    
    -- clean if required
    if _OPTIONS["clean"] then
        print('cleaning dir: ' .. build_dir)
        os.rmdir(build_dir)
    end

    if not os.mkdir(build_dir) then
        error("failed to create build dir: " .. build_dir)
        return
    end

    local install_dir = path.join(dep_base, 'install' .. arch_iden)
    local cmake_common_defs_str = '-D' .. table.concat(cmake_common_defs, ' -D') .. ' -DCMAKE_INSTALL_PREFIX="' .. install_dir .. '"'
    local cmd_gen = mycmake .. ' -S "' .. dep_base .. '" -B "' .. build_dir .. '" ' .. cmake_common_defs_str

    local all_cflags_init = {}
    local all_cxxflags_init = {}

    -- c/cxx init flags based on arch/action
    if string.match(_ACTION, 'gmake.*') then
        if is_32 then
            table.insert(all_cflags_init, '-m32')
            table.insert(all_cxxflags_init, '-m32')
        end
        if os.target() == 'windows' then -- MinGW on Windows
            table.insert(all_cflags_init, '-static')
            table.insert(all_cxxflags_init, '-static')
            -- from docs: "specifies that the typical Microsoft Windows predefined macros are to be set in the pre-processor,
            --             but does not influence the choice of runtime library/startup code"
            -- optional really
            table.insert(all_cflags_init, '-mwin32')
            table.insert(all_cxxflags_init, '-mwin32')
        end
    elseif string.match(_ACTION, 'vs.+') then
        -- these 2 are needed because mbedtls doesn't care about 'CMAKE_MSVC_RUNTIME_LIBRARY' for some reason
        table.insert(all_cflags_init, '-MT')
        table.insert(all_cflags_init, '-D_MT')

        table.insert(all_cxxflags_init, '-MT')
        table.insert(all_cxxflags_init, '-D_MT')
        
        if is_32 then
            cmd_gen = cmd_gen .. ' -A Win32'
        else
            cmd_gen = cmd_gen .. ' -A x64'
        end
    else
        error("unsupported action for cmake build: " .. _ACTION)
        return
    end
    
    -- add c/cxx extra init flags
    if c_flags_init then
        if type(c_flags_init) ~= 'table' then
            error("unsupported type for c_flags_init: " .. type(c_flags_init))
            return
        end
        for _, cval in pairs(c_flags_init) do
            table.insert(all_cflags_init, cval)
        end
    end
    if cxx_flags_init then
        if type(cxx_flags_init) ~= 'table' then
            error("unsupported type for cxx_flags_init: " .. type(cxx_flags_init))
            return
        end
        for _, cval in pairs(cxx_flags_init) do
            table.insert(all_cxxflags_init, cval)
        end
    end
    -- convert to space-delimited str
    local cflags_init_str = ''
    if #all_cflags_init > 0 then
        cflags_init_str = '"' .. table.concat(all_cflags_init, " ") .. '"'
    end
    local cxxflags_init_str = ''
    if #all_cxxflags_init > 0 then
        cxxflags_init_str = '"' .. table.concat(all_cxxflags_init, " ") .. '"'
    end

    -- write toolchain file
    local toolchain_file_content = ''
    if #cflags_init_str > 0 then
        toolchain_file_content = toolchain_file_content .. 'set(CMAKE_C_FLAGS_INIT ' .. cflags_init_str .. ' )\n'
    end
    if #cxxflags_init_str > 0 then
        toolchain_file_content = toolchain_file_content .. 'set(CMAKE_CXX_FLAGS_INIT ' .. cxxflags_init_str .. ' )\n'
    end

    if #toolchain_file_content > 0 then
        local toolchain_file = path.join(dep_base, 'toolchain_' .. tostring(is_32) .. '_' .. _ACTION .. '_' .. os.target() .. '.precmt')
        if not io.writefile(toolchain_file, toolchain_file_content) then
            error("failed to write cmake toolchain")
            return
        end
        cmd_gen = cmd_gen .. ' -DCMAKE_TOOLCHAIN_FILE="' .. toolchain_file .. '"'
    end

    -- add extra defs
    if extra_cmd_defs then
        if type(extra_cmd_defs) ~= 'table' then
            error("unsupported type for extra_cmd_defs: " .. type(extra_cmd_defs))
            return
        end
        if #extra_cmd_defs > 0 then
            local extra_defs_str = ' -D' .. table.concat(extra_cmd_defs, ' -D')
            cmd_gen = cmd_gen .. extra_defs_str
        end
    end

    -- verbose generation
    if _OPTIONS['verbose'] then
        print(cmd_gen)
    end

    -- generate cmake config
    local ok = os.execute(cmd_gen)
    if not ok then
        error("failed to generate")
        return
    end

    -- verbose build
    local verbose_build_str = ''
    if _OPTIONS['verbose'] then
        verbose_build_str = ' -v'
    end

    -- build with cmake
    local ok = os.execute(mycmake .. ' --build "' .. build_dir .. '" --config Release --parallel' .. verbose_build_str)
    if not ok then
        error("failed to build")
        return
    end

    -- clean if required
    if _OPTIONS["clean"] then
        print('cleaning dir: ' .. install_dir)
        os.rmdir(install_dir)
    end
    -- create dir
    if not os.mkdir(install_dir) then
        error("failed to create install dir: " .. install_dir)
        return
    end

    local cmd_install = mycmake.. ' --install "' .. build_dir .. '" --prefix "' .. install_dir .. '"'
    print(cmd_install)
    local ok = os.execute(cmd_install)
    if not ok then
        error("failed to install")
        return
    end
end

if os.host() == "linux" then
    local ok_chmod, err_chmod = os.chmod(extractor, "777")
    if not ok_chmod then
        error("cannot chmod: " .. err_chmod)
        return
    end

    if not _OPTIONS["custom-cmake"] then
        local ok_chmod, err_chmod = os.chmod(mycmake, "777")
        if not ok_chmod then
            error("cannot chmod: " .. err_chmod)
            return
        end
    end
end


-- extract action
-------
deps_to_extract = {} -- { 'path/to/archive', 'path/to/extraction folder'
if _OPTIONS["ext-ssq"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'libssq/libssq.tar.gz', 'libssq' })
end
if _OPTIONS["ext-zlib"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'zlib/zlib.tar.gz', 'zlib' })
end
if _OPTIONS["ext-curl"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'curl/curl.tar.gz', 'curl' })
end
if _OPTIONS["ext-protobuf"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'protobuf/protobuf.tar.gz', 'protobuf' })
end
if _OPTIONS["ext-mbedtls"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'mbedtls/mbedtls.tar.gz', 'mbedtls' })
end
if _OPTIONS["ext-ingame_overlay"] or _OPTIONS["all-ext"] then
    table.insert(deps_to_extract, { 'ingame_overlay/ingame_overlay.tar.gz', 'ingame_overlay' })
end


for _, dep in pairs(deps_to_extract) do
    -- check archive
    local archive_file = path.join(third_party_common_dir, dep[1])
    print('\n\nextracting dep archive: "' .. archive_file .. '"')

    if not os.isfile(archive_file) then
        error("archive not found: " .. archive_file)
        return
    end

    local out_folder = path.join(deps_dir, dep[2])

    -- clean if required
    if _OPTIONS["clean"] then
        print('cleaning dir: ' .. out_folder)
        os.rmdir(out_folder)
    end

    -- create out folder
    print("creating dir: " .. out_folder)
    local ok_mk, err_mk = os.mkdir(out_folder)
    if not ok_mk then
        error("Error: " .. err_mk)
        return
    end

    -- extract
    print("extracting: '" .. archive_file .. "'")
    local ext = string.lower(string.sub(archive_file, -7)) -- ".tar.gz"
    local ok_cmd = false
    if ext == ".tar.gz" then
        ok_cmd = os.execute(extractor .. ' -bso0 -bse2 x "' .. archive_file .. '" -so | "' .. extractor .. '" -bso0 -bse2 x -si -ttar -y -aoa -o"' .. out_folder .. '"')
    else
        ok_cmd = os.execute(extractor .. ' -bso0 -bse2 x "' .. archive_file .. '" -y -aoa -o"' .. out_folder .. '"')
    end
    if not ok_cmd then
        error('extraction failed')
    end

    -- flatten dir by moving all folders contents outside (one level above)
    print('flattening dir: ' .. out_folder)
    local folders = os.matchdirs(out_folder .. '/*')
    for _, inner_folder in pairs(folders) do
        -- the weird "/*" at the end is not a mistake, premake uses cp cpmmand on linux, which won't copy inner dir otherwise
        local ok = os.execute('{COPYDIR} "' .. inner_folder  .. '"/* "' .. out_folder .. '"')
        if not ok then
            error('copy dir failed, src=' .. inner_folder .. ', dest=' .. out_folder)
        end
        os.rmdir(inner_folder)
    end

end


-- build action
-------
if _OPTIONS["build-ssq"] or _OPTIONS["all-build"] then
    if _OPTIONS["32-build"] then
        cmake_build('libssq', true)
    end
    if _OPTIONS["64-build"] then
        cmake_build('libssq', false)
    end
end
if _OPTIONS["build-zlib"] or _OPTIONS["all-build"] then
    if _OPTIONS["32-build"] then
        cmake_build('zlib', true)
    end
    if _OPTIONS["64-build"] then
        cmake_build('zlib', false)
    end
end

-- ############## zlib is painful ##############
-- lib curl uses the default search paths, even when ZLIB_INCLUDE_DIR and ZLIB_LIBRARY_RELEASE are defined
-- check thir CMakeLists.txt line #573
--     optional_dependency(ZLIB)
--     if(ZLIB_FOUND)
--       set(HAVE_LIBZ ON)
--       set(USE_ZLIB ON)
--     
--       # Depend on ZLIB via imported targets if supported by the running
--       # version of CMake.  This allows our dependents to get our dependencies
--       # transitively.
--       if(NOT CMAKE_VERSION VERSION_LESS 3.4)
--         list(APPEND CURL_LIBS ZLIB::ZLIB)    <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< evil
--       else()
--         list(APPEND CURL_LIBS ${ZLIB_LIBRARIES})
--         include_directories(${ZLIB_INCLUDE_DIRS})
--       endif()
--       list(APPEND CMAKE_REQUIRED_INCLUDES ${ZLIB_INCLUDE_DIRS})
--     endif()
-- we have to set the ZLIB_ROOT so that it is prepended to the search list
-- we have to set ZLIB_LIBRARY NOT ZLIB_LIBRARY_RELEASE in order to override the FindZlib module
-- we also should set ZLIB_USE_STATIC_LIBS since we want to force static builds
-- https://github.com/Kitware/CMake/blob/a6853135f569f0b040a34374a15a8361bb73901b/Modules/FindZLIB.cmake#L98C4-L98C13

local zlib_name = ''
-- name
if os.target() == 'windows' then
    if string.match(_ACTION, 'vs.+') then
        zlib_name = 'zlibstatic'
    elseif string.match(_ACTION, 'gmake.*') then
        zlib_name = 'libzlibstatic'
    else
        error('unsupported os/action: ' .. os.target() .. ' / ' .. _ACTION)
    end
else -- linux or macos
    zlib_name = 'libz'
end
-- extension
if string.match(_ACTION, 'vs.+') then
    zlib_name = zlib_name .. '.lib'
else
    zlib_name = zlib_name .. '.a'
end

local wild_zlib_path_32 = path.join(deps_dir, 'zlib', 'install32', 'lib', zlib_name)
local wild_zlib_32 = {
    'ZLIB_USE_STATIC_LIBS=ON',
    'ZLIB_ROOT="' .. path.join(deps_dir, 'zlib', 'install32') .. '"',
    'ZLIB_INCLUDE_DIR="' .. path.join(deps_dir, 'zlib', 'install32', 'include') .. '"',
    'ZLIB_LIBRARY="' .. wild_zlib_path_32 .. '"',
}
local wild_zlib_path_64 = path.join(deps_dir, 'zlib', 'install64', 'lib', zlib_name)
local wild_zlib_64 = {
    'ZLIB_USE_STATIC_LIBS=ON',
    'ZLIB_ROOT="' .. path.join(deps_dir, 'zlib', 'install64') .. '"',
    'ZLIB_INCLUDE_DIR="' .. path.join(deps_dir, 'zlib', 'install64', 'include') .. '"',
    'ZLIB_LIBRARY="' .. wild_zlib_path_64 .. '"',
}

if _OPTIONS["build-curl"] or _OPTIONS["all-build"] then
    local curl_common_defs = {
        "BUILD_CURL_EXE=OFF",
        "BUILD_SHARED_LIBS=OFF",
        "BUILD_STATIC_CURL=OFF",
        "BUILD_STATIC_LIBS=ON",
        "CURL_USE_OPENSSL=OFF",
        "CURL_ZLIB=ON",
        "CURL_USE_LIBSSH2=OFF",
        "CURL_USE_LIBPSL=OFF",
        "USE_LIBIDN2=OFF",
        "CURL_DISABLE_LDAP=ON",
    }
    if os.target() == 'windows' and string.match(_ACTION, 'vs.+') then
        table.insert(curl_common_defs, "CURL_STATIC_CRT=ON")
        table.insert(curl_common_defs, "ENABLE_UNICODE=ON")
    end

    if _OPTIONS["32-build"] then
        cmake_build('curl', true, merge_list(merge_list(curl_common_defs, wild_zlib_32), {
            'CMAKE_SHARED_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
            'CMAKE_MODULE_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
            'CMAKE_EXE_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
        }))
    end
    if _OPTIONS["64-build"] then
        cmake_build('curl', false, merge_list(merge_list(curl_common_defs, wild_zlib_64), {
            'CMAKE_SHARED_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
            'CMAKE_MODULE_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
            'CMAKE_EXE_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
        }))
    end
end

if _OPTIONS["build-protobuf"] or _OPTIONS["all-build"] then
    local proto_common_defs = {
        "protobuf_BUILD_TESTS=OFF",
        "protobuf_BUILD_SHARED_LIBS=OFF",
        "protobuf_WITH_ZLIB=ON",
    }
    if _OPTIONS["32-build"] then
        cmake_build('protobuf', true, merge_list(merge_list(proto_common_defs, wild_zlib_32), {
            'CMAKE_SHARED_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
            'CMAKE_MODULE_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
            'CMAKE_EXE_LINKER_FLAGS_INIT="' .. wild_zlib_path_32 .. '"',
        }))
    end
    if _OPTIONS["64-build"] then
        cmake_build('protobuf', false, merge_list(merge_list(proto_common_defs, wild_zlib_64), {
            'CMAKE_SHARED_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
            'CMAKE_MODULE_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
            'CMAKE_EXE_LINKER_FLAGS_INIT="' .. wild_zlib_path_64 .. '"',
        }))
    end
end

if _OPTIONS["build-mbedtls"] or _OPTIONS["all-build"] then
    local mbedtls_common_defs = {
        "USE_STATIC_MBEDTLS_LIBRARY=ON",
        "USE_SHARED_MBEDTLS_LIBRARY=OFF",
        "ENABLE_TESTING=OFF",
        "ENABLE_PROGRAMS=OFF",
    }
    if os.target() == 'windows' and string.match(_ACTION, 'vs.+') then
        table.insert(mbedtls_common_defs, "MSVC_STATIC_RUNTIME=ON")
    else -- linux or macos or MinGW on Windows
        table.insert(mbedtls_common_defs, "LINK_WITH_PTHREAD=ON")
    end

    if _OPTIONS["32-build"] then
        cmake_build('mbedtls', true, mbedtls_common_defs, {
            '-mpclmul',
            '-msse2',
            '-maes',
        })
    end
    if _OPTIONS["64-build"] then
        cmake_build('mbedtls', false, mbedtls_common_defs)
    end
end

if _OPTIONS["build-ingame_overlay"] or _OPTIONS["all-build"] then
    -- fixes 32-bit compilation of DX12
    local overaly_imgui_cfg_file = path.join(deps_dir, 'ingame_overlay', 'imconfig.imcfg')
    if not io.writefile(overaly_imgui_cfg_file, [[
        #pragma once
        #define ImTextureID ImU64
    ]]) then
        error('failed to create ImGui config file for overlay: ' .. overaly_imgui_cfg_file)
    end

    local ingame_overlay_common_defs = {
        'IMGUI_USER_CONFIG="' .. overaly_imgui_cfg_file:gsub('\\', '/') .. '"', -- ensure we use '/' because this lib doesn't handle it well
        'INGAMEOVERLAY_USE_SYSTEM_LIBRARIES=OFF',
        'INGAMEOVERLAY_USE_SPDLOG=OFF',
        'INGAMEOVERLAY_BUILD_TESTS=OFF',
    }
    -- fix missing standard include/header file for gcc/clang
    local ingame_overlay_fixes = {}
    if string.match(_ACTION, 'gmake.*') then
        ingame_overlay_fixes = {
            '-include cstdint',
            '-include cinttypes',
        }
        -- MinGW fixes
        if os.target() == 'windows' then
            -- MinGW throws this error: Library.cpp:77:26: error: invalid conversion from 'FARPROC' {aka 'long long int (*)()'} to 'void*' [-fpermissive]
            table.insert(ingame_overlay_fixes, '-fpermissive')
            -- MinGW throws this error: Filesystem.cpp:139:38: error: no matching function for call to 'stat::stat(const char*, stat*)
            table.insert(ingame_overlay_fixes, '-include sys/stat.h')
        end
    end

    if _OPTIONS["32-build"] then
        cmake_build('ingame_overlay/deps/System', true, {
            'BUILD_SYSTEMLIB_TESTS=OFF',
        }, nil, ingame_overlay_fixes)
        cmake_build('ingame_overlay/deps/mini_detour', true, {
            'BUILD_MINIDETOUR_TESTS=OFF',
        })
        cmake_build('ingame_overlay', true, ingame_overlay_common_defs, nil, ingame_overlay_fixes)
    end
    if _OPTIONS["64-build"] then
        cmake_build('ingame_overlay/deps/System', false, {
            'BUILD_SYSTEMLIB_TESTS=OFF',
        }, nil, ingame_overlay_fixes)
        cmake_build('ingame_overlay/deps/mini_detour', false, {
            'BUILD_MINIDETOUR_TESTS=OFF',
        })
        cmake_build('ingame_overlay', false, ingame_overlay_common_defs, nil, ingame_overlay_fixes)
    end
end
