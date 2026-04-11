using System.Diagnostics;

if (args.Length != 1 || string.IsNullOrWhiteSpace(args[0]))
{
    return 1;
}

var scriptPath = args[0];
if (!File.Exists(scriptPath))
{
    return 2;
}

var workingDirectory = Path.GetDirectoryName(scriptPath) ?? Environment.CurrentDirectory;
var candidates = new[]
{
    @"C:\Program Files\PowerShell\7\pwsh.exe",
    @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
};

var host = candidates.FirstOrDefault(File.Exists);
if (host is null)
{
    return 3;
}

var psi = new ProcessStartInfo
{
    FileName = host,
    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
    WorkingDirectory = workingDirectory,
    UseShellExecute = false,
    CreateNoWindow = true,
    WindowStyle = ProcessWindowStyle.Hidden
};

Process.Start(psi);
return 0;
