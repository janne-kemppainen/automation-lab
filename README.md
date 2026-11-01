# automation-lab: Verkon automaatio Ansiblella

Korvaava laboratorio kurssille Verkonhallinta (HAMK). Tehtävänanto: [replacement.md](https://github.com/tjarvenpaa/Verkonhallinta/blob/main/docs/assignments/replacement.md)

**Tekijä:** Janne Kemppainen (tehty itsenäisesti, ei paria/ryhmää)

## Ympäristö

Harjoitus tehtiin kurssin Containerlab-ympäristössä (WSL2, Ubuntu 24.04) kampuksen Cisco-laitteiden sijaan.

| Rooli | Toteutus |
|---|---|
| Ansible-ohjausnode | WSL2-Ubuntu, Ansible core 2.16.3 (vastaa kampuslabran WSL-pohjaista Ansible-palvelinta) |
| Reitittimet | FRRouting 8.4 Alpine 3.16 -konteissa (`frrouting/frr`) |
| Projekti | tämä repo, `~/automation-lab` |

Tehtävänannossa reitittimet ovat nimeltään `r1-edge`, `r2-core` ja `r3-branch`, mutta kurssin topologiassa ne ovat `r1`, `r2` ja `r3`. Inventoryssa käytetään tehtävän nimiä ja `ansible_host` osoittaa todellisiin kontteihin.

### Miten Ansible kommunikoi reitittimien kanssa?

Ansible ottaa yhteyden SSH:lla Containerlabin hallintaverkon (172.20.20.0/24, rajapinta `eth0`) kautta. Konttien nimet (esim. `clab-hamk-verkonhallinta-golden-r1`) ratkeavat WSL:ssä hallintaosoitteiksi, koska Containerlab lisää ne isäntäkoneen `/etc/hosts`-tiedostoon. Inventoryssa käytetään nimiä eikä IP-osoitteita, koska hallintaosoitteet vaihtuvat jokaisessa labran käynnistyksessä.

| Reititin | Kontti | Hallintaosoite (tämä ajo) |
|---|---|---|
| r1-edge | clab-hamk-verkonhallinta-golden-r1 | 172.20.20.8 |
| r2-core | clab-hamk-verkonhallinta-golden-r2 | 172.20.20.4 |
| r3-branch | clab-hamk-verkonhallinta-golden-r3 | 172.20.20.13 |

Reitittimillä Ansible kirjautuu käyttäjänä `netadmin` SSH-avaimella, ja FRR:n komennot ajetaan `sudo vtysh -c "..."` (`ansible_become: true`). Ansible-moduulit toimivat, koska reitittimissä on `python3`.

### Day 0: SSH:n käyttöönotto

Ympäristön tarkistuksessa ([docs/replacement-env-check.txt](docs/replacement-env-check.txt)) selvisi, ettei reitittimissä ole SSH-palvelinta. Kampuslabrassa Cisco-laitteiden SSH konfiguroidaan ensin käsin konsolista ja vastaavasti tässä SSH otetaan käyttöön kertaluontoisella alustusskriptillä [bootstrap/enable-ssh.sh](bootstrap/enable-ssh.sh) (`docker exec`). Skripti:

- asentaa `openssh`- ja `sudo`-paketit
- luo käyttäjän `netadmin` ja lisää ohjausnoden julkisen avaimen
- estää salasanakirjautumisen (`PasswordAuthentication no`)
- käynnistää `sshd`:n

Reitittimet käyttävät suoraan `frrouting/frr`-kuvaa, joten niihin tehdyt muutokset eivät säily labran uudelleenkäynnistyksen yli. Skripti ajetaan siksi aina labran käynnistyksen jälkeen. Se on uudelleen ajettava, mutta se vaihtaa `netadmin`-käyttäjän (käyttämättömän) salasanan joka ajossa.

**Laboratorion kompromissit:**

- SSH-isäntäavainten tarkistus on pois päältä (`ansible.cfg`), koska reitittimet luovat uudet avaimet jokaisessa käynnistyksessä.
- `netadmin` saa sudon ilman salasanaa.
- Muutokset tehdään FRR:n ajonaikaiseen konfiguraatioon ilman `write memory` -komentoa, koska `/etc/frr/frr.conf` on liitetty kurssin repoon. Ajonaikaisen konfiguraation pysyvyys hoidetaan backupeilla ja playbookeilla.

## Rakenne

```text
automation-lab/
├── ansible.cfg              # inventory-polku ja SSH-asetukset
├── inventory/
│   ├── hosts.yml            # kolme reititintä
│   └── host_vars/
│       └── r3-branch.yml    # loopbackin haluttu tila (yksi lähde)
├── playbooks/
│   ├── facts.yml
│   ├── backup.yml
│   ├── loopback.yml
│   └── verify.yml
├── backups/                 # reitittimien running-config
├── facts/                   # facts.yml:n raportit
├── bootstrap/
│   └── enable-ssh.sh        # day 0: SSH reitittimille
└── docs/                    # komentojen tulosteet
```

Käyttö:

```bash
bash bootstrap/enable-ssh.sh
ansible-playbook playbooks/facts.yml
ansible-playbook playbooks/backup.yml
ansible-playbook playbooks/loopback.yml
ansible-playbook playbooks/verify.yml
```

## Toteutus ja tulokset

### 2. SSH-yhteydet ja inventaario

SSH-testi kahteen reitittimeen ([docs/ssh-test.txt](docs/ssh-test.txt)):

```text
r1
FRRouting 8.4_git (r1) on Linux(6.18.54.1-microsoft-standard-WSL2).
r3
FRRouting 8.4_git (r3) on Linux(6.18.54.1-microsoft-standard-WSL2).
```

`ansible-inventory --graph` ([docs/inventory-graph.txt](docs/inventory-graph.txt)):

```text
@all:
  |--@ungrouped:
  |--@routers:
  |  |--r1-edge
  |  |--r2-core
  |  |--r3-branch
```

Ansible-yhteystesti `ansible routers -m ping` ([docs/ansible-ping.txt](docs/ansible-ping.txt)): kaikki kolme `SUCCESS`. Koska yhteystapa on `ssh`, testi kirjautuu oikeasti reitittimelle ja ajaa siellä Python-moduulin.

### 3. Verkon automaattinen inventointi

[playbooks/facts.yml](playbooks/facts.yml) kerää yhdellä komennolla kaikista reitittimistä hostnamen, IP-osoitteet, interfacet, käyttöjärjestelmän, FRR-version ja uptimen, ja kirjoittaa jokaisesta raportin kansioon [facts/](facts/). Ajo: [docs/facts-run.txt](docs/facts-run.txt).

Uptime näytetään kahtena arvona. Ansiblen `ansible_uptime_seconds` lukee tiedoston `/proc/uptime`, joka konttiympäristössä kertoo WSL-isännän käyttöajan. Kontin oma käyttöaika lasketaan prosessin 1 käynnistyshetkestä.

| | r1-edge | r2-core | r3-branch |
|---|---|---|---|
| Interfacet | eth0–eth3, lo | eth0–eth4, lo | eth0–eth2, lo |
| Hallinta (eth0) | 172.20.20.8/24 | 172.20.20.4/24 | 172.20.20.13/24 |
| Siirtoyhteydet | 10.255.12.1/30 (→ r2) | 10.255.12.2/30 (→ r1), 10.255.23.1/30 (→ r3) | 10.255.23.2/30 (→ r2) |
| Lähiverkot | 10.10.10.1/24 ja 10.10.10.254/24 | 10.10.20.1/24, 10.10.99.1/24 | 10.10.30.1/24 |
| OS / FRR | Alpine 3.16.2 / 8.4 | Alpine 3.16.2 / 8.4 | Alpine 3.16.2 / 8.4 |

**Mitä eroja reitittimien interface- ja IP-konfiguraatioissa on?**

- **r2-core on verkon keskus.** Sillä on eniten rajapintoja ja kaksi siirtoyhteyttä, joten kaikki r1:n ja r3:n välinen liikenne kulkee sen kautta. Siihen on liitetty myös palvelinverkko (10.10.20.0/24) ja hallintaverkko (10.10.99.0/24).
- **r1-edge:llä on kaksi osoitetta samassa aliverkossa** (eth2 10.10.10.1 ja eth3 10.10.10.254). Tämä on epätavallinen ratkaisu, ja havaitsin sen jo kurssin viikolla 1.
- **r3-branch on yksinkertaisin:** yksi siirtoyhteys ja toimipisteen lähiverkko.
- r2:n FRR näkee lisäksi rajapinnan `clab-ea109e4a` tilassa down, jota käyttöjärjestelmän rajapintalistassa ei ole. Todennäköisesti se on Containerlabin väliaikainen rajapintanimi, jonka FRR rekisteröi ennen kuin rajapinta nimettiin uudelleen (ei varmennettu).
- Hallintaosoite (eth0) ei näy FRR:n konfiguraatiossa, koska sen asettaa Docker.

### 4. Konfiguraatioiden varmistaminen

[playbooks/backup.yml](playbooks/backup.yml) lukee jokaisen reitittimen `show running-config`:n ja tallentaa sen ohjausnodelle kansioon [backups/](backups/). `copy`-moduuli kirjoittaa tiedoston vain, jos sisältö on muuttunut, joten backup raportoi `changed` vain silloin, kun konfiguraatio on oikeasti muuttunut ([docs/backup-run1.txt](docs/backup-run1.txt), [docs/backup-run2.txt](docs/backup-run2.txt)).

### 5. Verkon tila Git-versionhallintaan

Ensimmäinen commit `Initial network state` sisältää lähtötilan backupit, inventoryn, playbookit ja alustusskriptin.

**Miksi verkkolaitteiden konfiguraatioita kannattaa säilyttää versionhallinnassa?**
Versionhallinnasta näkee, mikä konfiguraatio on ollut voimassa minäkin hetkenä, kuka sen muutti ja miksi (commit-viesti). Muutosta voi verrata aiempaan tilaan (`git diff`), ja virhetilanteessa tunnetun toimivan tilan saa haettua historiasta. Kun konfiguraatio on yhdessä paikassa, se toimii myös dokumentaationa ja auditointiaineistona.

### 6. Hallittu konfiguraatiomuutos

[playbooks/loopback.yml](playbooks/loopback.yml) luo r3-branchille rajapinnan `lo10` ja osoitteen `192.0.2.3/32`. Toteutuksessa on kaksi vaihetta, koska FRR:n `interface lo10` ei luo rajapintaa käyttöjärjestelmään:

1. Kerneliin luodaan `dummy`-rajapinta `lo10`, joka toimii Linuxissa kuin loopback.
2. Osoite asetetaan FRR:n konfiguraatioon `vtysh`:lla.

Playbook on kirjoitettu **halutun tilan** mukaan: se poistaa `lo10`:stä myös väärät osoitteet ja muuttaa vain sen, mikä poikkeaa halutusta tilasta. Halutut arvot ovat yhdessä paikassa, [inventory/host_vars/r3-branch.yml](inventory/host_vars/r3-branch.yml), josta sekä `loopback.yml` että `verify.yml` lukevat ne.

| Ajo | changed | Tulos |
|---|---|---|
| 1 ([docs/loopback-run1.txt](docs/loopback-run1.txt)) | 2 | kernel-rajapinta luotiin, FRR-osoite lisättiin |
| 2 ([docs/loopback-run2.txt](docs/loopback-run2.txt)) | **0** | tila oli jo oikea, mitään ei muutettu |

**Mitä tulos kertoo Ansiblen idempotenssista?**
Kun tila on jo oikea, toinen ajo ei muuta mitään. Playbookin voi siis ajaa turvallisesti uudelleen milloin tahansa. Idempotenssi ei kuitenkaan synny automaattisesti, kun käytetään `command`- tai `shell`-moduulia, koska Ansible ei tiedä, mitä komento tekee, ja raportoi oletuksena aina muutoksen. Tässä idempotenssi on toteutettu tarkistamalla nykytila ennen muutosta (`when`, tyhjä `loop`) ja kertomalla Ansiblelle, milloin muutos todella tapahtui (`changed_when`).

### 7. Muutoksen tarkistaminen

[playbooks/verify.yml](playbooks/verify.yml) tarkistaa `assert`-moduulilla, että:

- kaikki reitittimet vastaavat
- jokaisella on OSPF-naapuri Full-tilassa (reititys toimii yhä muutoksen jälkeen)
- `lo10` on olemassa
- `lo10`:ssä on osoite `192.0.2.3/32` ja vain se
- osoite on FRR:n konfiguraatiossa eikä pelkästään kernelissä

Tulos ([docs/verify-run1.txt](docs/verify-run1.txt)): r1-edge 1 Full, r2-core 2 Full, r3-branch 1 Full, ja `lo10 exists with exactly 192.0.2.3/32 in kernel and FRR`.

**Miksi muutoksen tekeminen ja sen onnistumisen tarkistaminen ovat eri asioita?**
Muutosplaybookin `ok`/`changed` kertoo vain, että komennot ajettiin ilman virhettä, ei sitä, että lopputulos on oikea. Tarkistus testaa lopputilan riippumatta siitä, miten siihen päädyttiin, ja huomaa myös sivuvaikutukset, kuten rikkoutuneen reitityksen. Tarkistuksen voi ajaa milloin tahansa, myös ilman muutosta, esim. käsin tehtyjen muutosten havaitsemiseen, kuten kohdassa 9.

### 8. Muutoksen tallentaminen

Uuden backupin jälkeen vain r3-branch muuttui, ja `git diff` näytti täsmälleen muutoksen:

```diff
+interface lo10
+ ip address 192.0.2.3/32
+exit
+!
```

### 9. Virhetilanne ja palautuminen

Simuloin ylläpitäjän käsin tekemää virhettä: kirjauduin r3:lle SSH:lla ja vaihdoin `lo10`:n osoitteen Ansiblen ohi:

```bash
sudo vtysh -c "configure terminal" -c "interface lo10" -c "no ip address 192.0.2.3/32" -c "ip address 192.0.2.33/32"
```

**Havaitseminen:** `verify.yml` epäonnistui ([docs/incident-1-verify-failed.txt](docs/incident-1-verify-failed.txt)):

```text
fatal: [r3-branch]: FAILED! => {
    "assertion": "('inet ' ~ lo_address) in kernel_lo.stdout",
    "msg": "lo10 is not in the expected state (192.0.2.3/32)"
}
```

r1 ja r2 sekä OSPF olivat kunnossa, joten vika rajautui r3:n loopbackiin.

**Selvitys Gitillä** ([docs/incident-2-diff.txt](docs/incident-2-diff.txt)):

```diff
 interface lo10
- ip address 192.0.2.3/32
+ ip address 192.0.2.33/32
```

1. **Mikä muuttui:** `lo10`:n osoite `192.0.2.3/32` → `192.0.2.33/32`.
2. **Mikä oli oikea konfiguraatio:** `-`-rivi, eli viimeisimpään committiin tallennettu versio.
3. **Tunnettu toimiva tila:** commit `Add branch loopback interface` (`git show HEAD:backups/r3-branch.conf`).

**Palautus Ansiblella** ([docs/incident-3-restore.txt](docs/incident-3-restore.txt)):

```text
TASK [Remove unexpected addresses from loopback]
changed: [r3-branch] => (item=192.0.2.33/32)
TASK [Configure loopback address in FRR]
changed: [r3-branch]
```

**Varmistus:** `verify.yml` meni läpi ([docs/incident-4-verify-ok.txt](docs/incident-4-verify-ok.txt)), ja uuden backupin jälkeen `git status --short backups/` oli tyhjä. Konfiguraatio palasi siis täsmälleen tunnettuun hyvään tilaan.

## Git-historia

```text
Recover from simulated loopback misconfiguration
Add branch loopback interface
Initial network state
```

## Vastaukset kysymyksiin

**1. Mitä hyötyä Ansible tarjoaa verrattuna reitittimien käsin konfigurointiin?**
Sama muutos tehdään yhdellä komennolla kaikille laitteille ja lopputulos on joka kerta sama. Playbook on samalla dokumentaatio siitä, miten verkko on konfiguroitu. Muutoksen voi tarkistaa (`verify.yml`) ja toistaa, ja tiedon keruu (`facts.yml`) ja varmistukset (`backup.yml`) onnistuvat kaikista laitteista kerralla. Käsin tehdyssä konfiguroinnissa jokainen laite on oma riskinsä: kirjoitusvirhe, unohtunut vaihe tai eri järjestys tuottaa erilaisen lopputuloksen.

**2. Mitä Ansiblen idempotenssi tarkoittaa käytännössä?**
Playbookin voi ajaa kuinka monta kertaa tahansa, ja se muuttaa vain sen, mikä poikkeaa halutusta tilasta. Tässä `loopback.yml` antoi ensimmäisellä ajolla `changed=2` ja toisella `changed=0`. Käytännössä idempotenssi tarkoittaa sitä, että playbookilla voi myös korjata tilan: virhetilanteessa sama playbook poisti väärän osoitteen ja palautti oikean, eikä erillistä palautusskriptiä tarvittu.

**3. Mitä hyötyä Git-versionhallinnasta on verkkolaitteiden hallinnassa?**
Git tallentaa verkon tilat ajassa. Virhetilanteessa `git diff` näytti heti, mikä muuttui ja mikä oli oikea arvo, ilman että konfiguraatiota tarvitsi verrata käsin. Commit-historiasta näkee, milloin ja miksi muutos tehtiin. Tunnetun hyvän tilan saa haettua historiasta ja `git status` vahvisti palautuksen jälkeen, että tila oli täsmälleen sama kuin ennen virhettä.

**4. Miten virtuaalisten FRRouting-reitittimien hallinta eroaa oikeiden verkkolaitteiden hallinnasta?**

| | FRR-kontit (tämä harjoitus) | Cisco IOS (kampuslabra) |
|---|---|---|
| Yhteys | Linux-SSH, Ansiblen `ssh`-yhteys ja Python-moduulit kohteessa | `network_cli`, IOS-komentorivi SSH:n yli, ei Pythonia laitteessa |
| Moduulit | Yleiset `command`/`shell` + `vtysh`. Idempotenssi piti rakentaa itse | Valmiit `cisco.ios`-moduulit (`ios_config`, `ios_facts`), joissa on sisäänrakennettu idempotenssi |
| Rajapinnat | Rajapinnan luonti vaati kernel-komennon (`ip link add ... type dummy`) | `interface Loopback10` luo rajapinnan suoraan |
| Pysyvyys | Kontti palautuu kuvan tilaan uudelleenkäynnistyksessä. SSH-alustus täytyy toistaa | `write memory` tallentaa konfiguraation laitteen muistiin |
| Hallintayhteys | Hallintaverkko valmiina (Containerlab), osoitteet vaihtuvat | Hallintaverkko ja SSH konfiguroidaan käsin konsolista |
| Resurssit | Jakavat isännän ytimen, CPU:n ja muistin | Oma laitteisto |

Virtuaaliympäristö on nopea, ilmainen ja turvallinen kokeilla, ja Linux-pohjaisuus antaa enemmän työkaluja. Toisaalta se ei vastaa kaikilta osin oikeaa laitetta, eikä valmistajakohtaisia moduuleja voi testata.

**5. Mitä tapahtui simuloidussa virhetilanteessa ja miten palautit oikean konfiguraation?**
Vaihdoin r3-branchin `lo10`-osoitteen käsin Ansiblen ohi arvoon `192.0.2.33/32`. `verify.yml` havaitsi virheen (oikeaa osoitetta ei löytynyt) ja osoitti samalla, että muu verkko ja OSPF toimivat. Uuden backupin `git diff` näytti, että osoite oli muuttunut, ja viimeisin commit kertoi oikean arvon. Palautin tilan ajamalla `loopback.yml`:n uudelleen: koska playbook kuvaa halutun tilan, se poisti väärän osoitteen ja lisäsi oikean. `verify.yml` meni läpi ja uusi backup oli identtinen tunnetun hyvän tilan kanssa.

## Havaintoja ja kehitysajatuksia

- Ilman `host_vars`-tiedostoa samat arvot olisivat olleet kahdessa playbookissa ja ne olisivat voineet joutua ristiriitaan. Yksi lähde haluttua tilaa varten on IaC:n perusperiaate.
- Oikeissa laitteissa käyttäisin valmistajan moduuleja (`cisco.ios.ios_config`, `frr.frr`-kokoelma), jolloin idempotenssia ei tarvitsisi rakentaa itse.
- Tuotannossa SSH-isäntäavaimet tarkistettaisiin, salaisuudet hallittaisiin Ansible Vaultilla ja muutokset ajettaisiin ensin `--check --diff`-tilassa.
- `verify.yml`:n voisi ajaa ajastetusti, jolloin käsin tehdyt muutokset (configuration drift) havaittaisiin automaattisesti.