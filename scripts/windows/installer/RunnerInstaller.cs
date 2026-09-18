using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class RunnerInstaller : Form
{
    readonly TextBox token = new TextBox();
    readonly TextBox runnerName = new TextBox();
    readonly TextBox log = new TextBox();
    readonly Button install = new Button();
    bool installing;

    public RunnerInstaller()
    {
        Text = "CFOpt 四川移动 Runner 安装器";
        ClientSize = new Size(700, 570);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Microsoft YaHei UI", 10);
        Controls.Add(new Label { Text = "四川移动 · 德阳测点 → CMCC_SC.csv", Location = new Point(24, 20), AutoSize = true, Font = new Font(Font, FontStyle.Bold) });
        Controls.Add(new Label { Text = "安装后随开机后台运行，不需要一直开着此窗口。\n仅接收 CFOpt 四川移动任务，不覆盖成都或北京 CSV。", Location = new Point(24, 55), Size = new Size(650, 52) });
        Controls.Add(new Label { Text = "Runner 名称（每台机器要不同）", Location = new Point(24, 117), AutoSize = true });
        runnerName.SetBounds(24, 144, 650, 30);
        runnerName.Text = "cfopt-sc-" + Regex.Replace(Environment.MachineName, "[^A-Za-z0-9_-]", "-").ToLowerInvariant();
        if (runnerName.Text.Length > 64) runnerName.Text = runnerName.Text.Substring(0, 64);
        Controls.Add(runnerName);
        Controls.Add(new Label { Text = "仓库管理员提供的临时注册令牌（不是 GitHub 个人 Token）", Location = new Point(24, 186), AutoSize = true });
        token.SetBounds(24, 214, 650, 30);
        token.UseSystemPasswordChar = true;
        Controls.Add(token);
        Controls.Add(new Label { Text = "要求：Windows x64、Git for Windows、管理员权限和可访问 GitHub。\n此服务允许可信仓库在本机执行代码；仅安装在自愿参与的电脑上。", Location = new Point(24, 254), Size = new Size(650, 50) });
        var git = new LinkLabel { Text = "安装 Git for Windows", Location = new Point(24, 309), AutoSize = true };
        git.LinkClicked += delegate { Process.Start(new ProcessStartInfo("https://git-scm.com/download/win") { UseShellExecute = true }); };
        Controls.Add(git);
        install.Text = "安装后台服务";
        install.SetBounds(490, 302, 184, 36);
        install.Click += async delegate { await InstallAsync(); };
        Controls.Add(install);
        log.SetBounds(24, 353, 650, 194);
        log.Multiline = true; log.ReadOnly = true; log.ScrollBars = ScrollBars.Vertical;
        log.Font = new Font("Consolas", 9);
        Controls.Add(log);
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (installing) { e.Cancel = true; MessageBox.Show(this, "安装正在进行，请等待完成。", Text); } };
    }

    static string Script()
    {
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Install-Runner.ps1"))
        using (var reader = new StreamReader(stream, Encoding.UTF8)) return reader.ReadToEnd();
    }

    void Append(string value, string secret)
    {
        if (value == null) return;
        value = value.Replace(secret, "[REDACTED]");
        if (InvokeRequired) { BeginInvoke(new Action<string, string>(Append), value, secret); return; }
        log.AppendText(value + Environment.NewLine);
    }

    async Task InstallAsync()
    {
        string secret = token.Text.Trim();
        string name = runnerName.Text.Trim();
        if (!Regex.IsMatch(name, "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$") ||
            !Regex.IsMatch(secret, "^[A-Za-z0-9_-]+$") || secret.StartsWith("ghp_") || secret.StartsWith("github_pat_"))
        { MessageBox.Show(this, "请填写有效名称和临时 runner 注册令牌，不要填写个人访问 Token。", Text); return; }
        if (MessageBox.Show(this, "将下载官方 runner 并为 GuardSkill/CFOpt 安装开机启动服务。\n\n安装目录：C:\\ProgramData\\CFOpt\\runner-sc\n是否继续？", Text, MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
        installing = true; install.Enabled = false; token.Enabled = false; runnerName.Enabled = false;
        log.Clear();
        string temp = Path.Combine(Path.GetTempPath(), "cfopt-installer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        string script = Path.Combine(temp, "Install-Runner.ps1");
        try
        {
            File.WriteAllText(script, Script(), new UTF8Encoding(true));
            var info = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe"));
            info.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" -RunnerName \"" + name + "\"";
            info.UseShellExecute = false; info.CreateNoWindow = true;
            info.RedirectStandardOutput = true; info.RedirectStandardError = true;
            // Never embed or persist the registration token in the EXE, script or log.
            info.EnvironmentVariables["CFOPT_REGISTRATION_TOKEN"] = secret;
            int code = await Task.Run(delegate {
                using (var process = new Process { StartInfo = info }) {
                    process.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { Append(e.Data, secret); };
                    process.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { Append(e.Data, secret); };
                    process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine(); process.WaitForExit();
                    return process.ExitCode;
                }
            });
            token.Clear();
            MessageBox.Show(this, code == 0 ? "安装成功！可以关闭窗口。请让仓库管理员触发首次测速。" : "安装失败。请查看日志；不要直接删除已有 runner。", Text, MessageBoxButtons.OK, code == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Error);
        }
        catch (Exception ex) { Append(ex.Message, secret); MessageBox.Show(this, "安装失败，请查看日志。", Text); }
        finally {
            if (File.Exists(script)) File.Delete(script);
            if (Directory.Exists(temp)) Directory.Delete(temp);
            installing = false; install.Enabled = true; token.Enabled = true; runnerName.Enabled = true;
        }
    }

    [STAThread]
    static int Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        if (args.Length > 0 && args[0] == "--self-test")
        {
            if (!Script().Contains("--labels 'cfopt,sichuan,cmcc'") || !Script().Contains("Get-FileHash")) return 1;
            using (var form = new RunnerInstaller()) {
                form.StartPosition = FormStartPosition.Manual;
                form.Location = new Point(-3000, -3000);
                form.Show();
                Application.DoEvents();
                if (!form.token.UseSystemPasswordChar || !form.install.Enabled) return 2;
                if (args.Length > 1) {
                    using (var bitmap = new Bitmap(form.Width, form.Height)) {
                        form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                        bitmap.Save(args[1], System.Drawing.Imaging.ImageFormat.Png);
                    }
                }
            }
            return 0;
        }
        var principal = new WindowsPrincipal(WindowsIdentity.GetCurrent());
        if (!principal.IsInRole(WindowsBuiltInRole.Administrator)) {
            try { Process.Start(new ProcessStartInfo(Application.ExecutablePath) { UseShellExecute = true, Verb = "runas" }); return 0; }
            catch { MessageBox.Show("需要管理员权限才能安装后台服务。取消后不会安装。", "CFOpt"); return 1; }
        }
        Application.Run(new RunnerInstaller());
        return 0;
    }
}
