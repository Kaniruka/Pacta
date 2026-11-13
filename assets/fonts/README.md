# MiSans

Pacta uses the official MiSans Version 4.009 TrueType fonts for its bundled
UI typography. The four regular, medium, semibold, and bold files total
32,270,460 bytes.

The font binaries are excluded from Git. On the first local build, run:

```powershell
python scripts/fetch_misans.py
```

The script checks local files first and exits without networking when all
four match their SHA256 digests. If files are missing, it downloads the Xiaomi
archive, verifies all four source files, and writes only the missing unchanged
TTFs. A local file with an unexpected digest causes an error without being
overwritten. The script does not alter or subset the fonts and does not accept
any license agreement on the user's behalf.

Xiaomi's official [FAQ](https://hyperos.mi.com/font/faq) says MiSans may be
embedded in software and requires the software to specifically indicate that
it uses MiSans. Pacta provides that notice in the app. The [official MiSans
Font Intellectual Property License Agreement](https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf)
also requires retaining its copyright notice and agreement with any font copy,
and restricts separately distributing font software or copies. This repository
does not mirror the raw font files; the setup script fetches them from Xiaomi.

Official source archive: <https://hyperos.mi.com/font-download/MiSans.zip>
