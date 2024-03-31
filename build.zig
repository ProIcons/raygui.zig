const std = @import("std");
const generate = @import("generate.zig");

const rayguiSrc = "raygui/src/";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    //--- parse raygui and generate JSONs for all signatures --------------------------------------
    const jsons = b.step("parse", "parse raygui headers and generate raylib parser output as json");
    const raylib_parser_build = b.addExecutable(.{
        .name = "raylib_parser",
        .root_source_file = std.Build.LazyPath.relative("raylib_parser.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    raylib_parser_build.addCSourceFile(.{ .file = .{ .path = "../raylib/raylib/parser/raylib_parser.c" }, .flags = &.{} });
    raylib_parser_build.linkLibC();

    //raygui
    const raygui_H = b.addRunArtifact(raylib_parser_build);
    raygui_H.addArgs(&.{
        "-i", "raygui/src/raygui.h",
        "-o", "raygui.json",
        "-f", "JSON",
        "-d", "RAYGUIAPI",
    });
    jsons.dependOn(&raygui_H.step);

    //--- Generate intermediate -------------------------------------------------------------------
    const intermediate = b.step("intermediate", "generate intermediate representation of the results from 'zig build parse' (keep custom=true)");
    var intermediateZig = b.addRunArtifact(b.addExecutable(.{
        .name = "intermediate",
        .root_source_file = std.Build.LazyPath.relative("intermediate.zig"),
        .target = target,
    }));
    intermediate.dependOn(&intermediateZig.step);

    //--- Generate bindings -----------------------------------------------------------------------
    const bindings = b.step("bindings", "generate bindings in from bindings.json");
    var generateZig = b.addRunArtifact(b.addExecutable(.{
        .name = "generate",
        .root_source_file = std.Build.LazyPath.relative("generate.zig"),
        .target = target,
    }));
    const fmt = b.addFmt(.{ .paths = &.{generate.outputFile} });
    fmt.step.dependOn(&generateZig.step);
    bindings.dependOn(&fmt.step);

    //--- just build raylib_parser.exe ------------------------------------------------------------
    const raylib_parser_install = b.step("raylib_parser", "build ./zig-out/bin/raylib_parser.exe");
    const generateBindings_install = b.addInstallArtifact(raylib_parser_build, .{});
    raylib_parser_install.dependOn(&generateBindings_install.step);
}

// above: generate library
// below: linking (use as dependency)

fn current_file() []const u8 {
    return @src().file;
}

const cwd = std.fs.path.dirname(current_file()).?;
const sep = std.fs.path.sep_str;
const dir_raygui = cwd ++ sep ++ "raygui/src";

/// add this package to lib
pub fn addTo(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    target: std.Target.Query,
    optimize: std.builtin.Mode,
) void {
    if (lib.root_module.import_table.get("raylib") orelse lib.root_module.import_table.get("raylib.zig") orelse lib.root_module.import_table.get("raylib-zig")) |raylib| {
        const rayguiLib = b.addStaticLibrary(
            .{
                .name = "raygui.zig",
                .target = b.resolveTargetQuery(target),
                .optimize = optimize,
                .root_source_file = .{ .path = cwd ++ sep ++ "raygui.zig" },
            },
        );

        rayguiLib.linkLibC();

        for (raylib.include_dirs.items) |includedItem| {
            rayguiLib.addIncludePath(includedItem.path);
        }

        rayguiLib.addIncludePath(.{ .path = dir_raygui });
        rayguiLib.addIncludePath(.{ .path = cwd });
        rayguiLib.addCSourceFile(.{ .file = .{ .path = cwd ++ sep ++ "raygui_marshal.c" }, .flags = &.{"-DRAYGUI_IMPLEMENTATION"} });
        rayguiLib.root_module.addImport("raylib", raylib);

        lib.root_module.addImport("raygui", &rayguiLib.root_module);
    } else {
        std.debug.panic("lib needs to have 'raylib', 'raylib.zig' or 'raylib-zig' as module dependency", .{});
    }
}
