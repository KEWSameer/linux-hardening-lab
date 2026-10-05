# Ubuntu Server Hardening Lab

I built this lab to practice basic Linux security on a real server setup without spending any money. I installed a fresh Ubuntu Server in VirtualBox, measured it with Lynis, and then hardened it step by step. This README shows what I did, why I did it, and what the results were.

**Result:** Lynis hardening index went from **61 to 66**.

## Lab Environment

| Item | Value |
| :--- | :--- |
| Hypervisor | Oracle VirtualBox on Windows |
| Guest OS | Ubuntu Server 26.04.1 LTS |
| CPU | 2 cores |
| RAM | 2 GB |
| Storage | 20 GB |
| Network | NAT with a port forward |
| Access | SSH from Windows PowerShell |

The VM sits behind VirtualBox NAT, so my Windows machine cannot reach it directly. I added a port forwarding rule: host `127.0.0.1` port `2222` to guest port `22`. SSH inside the VM stays on the standard port 22. Port 2222 only exists on my Windows host.

## What I Did

### 1. Baseline audit

I installed Ubuntu Server, ran `apt update`, and installed Lynis. Before I changed anything, I ran an audit to get a starting score.

```bash
sudo apt update
sudo apt install lynis -y
sudo lynis audit system
```

Baseline hardening index: **61**

### 2. Remote access over SSH

Working inside the VirtualBox window is slow and has no copy and paste, so I set up SSH first. I added the port forward rule in VirtualBox, installed the SSH server, enabled it, and connected from PowerShell.

```bash
sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```

```powershell
ssh sameer@127.0.0.1 -p 2222
```

### 3. Automatic security updates

Unpatched software is one of the most common ways attackers get in, so I turned on unattended upgrades.

```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades
```

I checked the log to confirm it works. The service ran a full upgrade and ended with "All upgrades installed".

![Unattended upgrades log](screenshots/unattended-upgrades-log.png)

### 4. Extra admin user

I created a second user and added it to the `sudo` group. This gives me a named account with an audit trail instead of a shared login.

```bash
sudo adduser khalid
sudo usermod -aG sudo khalid
```

### 5. Brute force protection with Fail2ban

Fail2ban watches the SSH logs and bans IP addresses that fail to log in too many times.

```bash
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
```

To test it, I made failed login attempts from a second PowerShell window and checked the jail:

```bash
sudo fail2ban-client status sshd
```

```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 1
|  |- Total failed: 4
|  `- Journal matches: _SYSTEMD_UNIT=ssh.service + _COMM=sshd
`- Actions
   |- Currently banned: 0
   |- Total banned: 0
   `- Banned IP list:
```

Fail2ban detected my failed attempts, but it did not ban anything. I made 4 failed attempts, and the default limit is 5, so I stayed under the threshold. The jail works and counts failures correctly. In a later round I want to trigger a real ban to see the full cycle.

### 6. SSH key authentication

Passwords are easy to guess and brute force. Keys are not. I created the `.ssh` folder on the server with strict permissions, generated an ed25519 key on Windows, and copied the public key over.

On the server:

```bash
mkdir ~/.ssh && chmod 700 ~/.ssh
```

On Windows PowerShell:

```powershell
ssh-keygen -t ed25519
scp -P 2222 $env:USERPROFILE\.ssh\id_ed25519.pub sameer@127.0.0.1:~/.ssh/authorized_keys
```

I tested the key login before touching the SSH config. It worked on the first try.

### 7. SSH hardening

After I confirmed that key login works, I locked down `/etc/ssh/sshd_config`:

```
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
```

| Setting | Why |
| :--- | :--- |
| `AddressFamily inet` | SSH listens on IPv4 only. I do not use IPv6, so I closed that door. |
| `PermitRootLogin no` | Attackers always try the `root` username first. Now it is blocked. |
| `PasswordAuthentication no` | Only my key gets in. Password guessing no longer works. |
| `MaxAuthTries 3` | Each connection gets 3 attempts before SSH drops it. |

```bash
sudo systemctl restart ssh
```

I tested key access before I disabled passwords, so a typo would not lock me out of my own server.

### 8. Permissions and log review

I reviewed `/etc/passwd`, `/etc/shadow`, and the sudo rules. `/etc/shadow` is readable only by root and the shadow group, which is correct because it stores password hashes.

I also looked for my own failed login in `/var/log/auth.log`:

```
2026-10-05T17:40:26.922781+00:00 ubuntu sshd-session[47603]: Connection reset by authenticating user sameer 10.0.2.2 port 54750 [preauth]
```

The source address `10.0.2.2` is the VirtualBox NAT gateway, which is my Windows host. Every connection from my own machine looks like it comes from that address.

### 9. Final audit

I ran Lynis again after all the changes.

```bash
sudo lynis audit system
```

Final hardening index: **66**

## Results

| Measure | Before | After |
| :--- | :---: | :---: |
| Lynis hardening index | 61 | 66 |
| Root SSH login | Allowed | Blocked |
| SSH password login | Allowed | Blocked |
| SSH IP version | IPv4 and IPv6 | IPv4 only |
| Automatic security updates | Off | On |
| Brute force protection | None | Fail2ban active |

## Remaining Findings

Lynis still lists suggestions. I chose not to fix these because they do not fit a single-user lab VM:

| Suggestion | Why I skipped it |
| :--- | :--- |
| Separate `/home` and `/var` partitions | It needs a full reinstall and adds little value on a small lab disk. |
| GRUB boot password | Nobody has physical access to this VM, and a forgotten password would lock me out. |
| External log host | It needs a second server. |

Lynis scores against a general checklist, so a higher number does not always mean a better fit. I picked the changes that matter for my threat model and skipped the rest on purpose.

## Troubleshooting

**SSH: Connection refused on 127.0.0.1:2222**
The port forward rule was in place, but the SSH server was not installed yet, so nothing listened on port 22. I installed `openssh-server`, enabled it, and the connection worked.

**PowerShell: command not recognized**
I typed `sameer@127.0.0.1 -p 2222` without `ssh` at the start. PowerShell treated the address as a program name. The fix was to put `ssh` in front of the command.

## What I Learned

- Test key login before you disable password login. One mistake in `sshd_config` can lock you out of your own server.
- A Lynis score is a guide, not a goal. The report taught me more than the number did.
- Fail2ban counts failures per jail. Staying under the limit means no ban, so testing it needs enough failed attempts.

## Next Steps

- Turn my commands into `scripts/harden.sh`, then extend it to check each setting and print pass or fail
- Trigger a real Fail2ban ban and record the output
- Add a firewall with UFW and document the before and after open ports
