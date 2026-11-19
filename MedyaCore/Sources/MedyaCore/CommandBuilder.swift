import Foundation

public enum CommandBuilder {
    public static func infoArguments(_ r: DownloadRequest, tools: ToolPaths) -> [String] {
        var args = cookieArguments(r) + ["--ignore-config", "--no-playlist", "-J"]
        if r.site == .youtube {
            args += ["--remote-components", "ejs:github", "--js-runtimes", "deno:\(tools.deno.path)"]
        }
        args.append(r.url.absoluteString)
        return args
    }

    public static func ytdlpArguments(_ r: DownloadRequest, tools: ToolPaths) -> [String] {
        var args = cookieArguments(r) + [
            "--ignore-config",
            "--no-playlist",
            "--ffmpeg-location", tools.ffmpegDir.path,
            "--newline",
            "--progress",
            "--progress-template",
            "download:MI|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s",
            "--print", "after_move:filepath",
            "-P", FolderLayout.root(in: r.destination).path,
            "-o", FolderLayout.ytdlpOutputTemplate(r),
            "--windows-filenames",
        ]
        if r.site == .youtube {
            args += ["--remote-components", "ejs:github", "--js-runtimes", "deno:\(tools.deno.path)"]
        }
        switch r.format {
        case .video(let height):
            let selector = height.map { "bv*[height<=\($0)]+ba/b[height<=\($0)]" } ?? "bv*+ba/b"
            args += ["-f", selector, "--merge-output-format", "mp4", "-S", "res,vcodec:h264,acodec:m4a"]
            // --write-subs verilmez: verilirse yt-dlp gömdükten sonra .vtt dosyalarını da klasörde bırakır.
            if r.subtitles, r.site == .youtube {
                args += ["--write-auto-subs", "--sub-langs", "tr,en", "--embed-subs"]
            }
        case .audio(let kbps):
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "\(kbps)K"]
        case .images:
            preconditionFailure("Görseller yalnızca gallery-dl ile indirilir")
        }
        args.append(r.url.absoluteString)
        return args
    }

    public static func galleryDLArguments(_ r: DownloadRequest) -> [String] {
        cookieArguments(r) + [
            "--config-ignore",
            "-d", FolderLayout.root(in: r.destination).path,
            "-o", "directory=" + FolderLayout.galleryDLDirectory(r),
            r.url.absoluteString,
        ]
    }

    private static func cookieArguments(_ r: DownloadRequest) -> [String] {
        r.useCookies ? ["--cookies-from-browser", r.browser.rawValue] : []
    }
}
