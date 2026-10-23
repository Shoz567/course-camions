// Jeu a partager (make share, 2026-10-23 : « un fichier que je puisse partager
// a mes amis pour qu'on puisse jouer ensemble ») : deux archives pretes a
// envoyer, chacune avec un dossier CrazyWheels/ et une notice.
//
//   builds/CrazyWheels-Windows.zip  CrazyWheels.exe + .pck, Assets_Visuels/, LISEZ-MOI
//   builds/CrazyWheels-Mac.zip      Crazy Wheels.app, Assets_Visuels/, LISEZ-MOI
//
// Les modeles des camions (Assets_Visuels, Git LFS) sont lus a cote du jeu
// (TruckVisual.asset_base) : sur Mac, a cote de l'application, pas dedans
// (y ajouter un fichier casserait sa signature). L'application Mac est recopiee
// telle que Godot l'a produite (donnees et attributs Unix de chaque entree) :
// un zip refait sous Windows perd le droit d'execution, et macOS refuse alors
// de lancer le jeu. Ne pas recompresser le zip Mac sous Windows.
// Une application telechargee et non signee par Apple est lancee depuis une
// copie cachee (App Translocation), sans le dossier Assets_Visuels a cote :
// la notice fait retirer la quarantaine de tout le dossier (xattr -cr) avant
// le premier lancement.
//
// Windows : CrazyWheels.exe est l'executable officiel de Godot, signe par son
// editeur, renomme ; il charge CrazyWheels.pck pose a cote. Le modele d'export
// n'est pas signe, et le controle intelligent des applications de Windows 11
// bloquait le jeu sans recours (2026-10-23). Ne pas remplacer cet executable
// par builds/windows/CrazyWheels.exe.
//
// Zip ecrit a la main (Node, sans dependance) : entrees stockees ou
// deflate, attributs Unix, pas de Zip64 (archives < 4 Go).

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.resolve(__dirname, "..");
const BUILDS = path.join(ROOT, "builds");
const TOP = "CrazyWheels/";

function dosTime(d) {
	const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
	const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
	return [time, date];
}

class ZipWriter {
	constructor(file) {
		this.fd = fs.openSync(file, "w");
		this.offset = 0;
		this.central = [];
		[this.time, this.date] = dosTime(new Date());
	}

	_write(buf) {
		fs.writeSync(this.fd, buf);
		this.offset += buf.length;
	}

	// Entree deja compressee : nom, donnees, methode, crc, taille, attributs.
	raw(name, data, method, crc, size, extAttr, madeBy) {
		const nameBuf = Buffer.from(name, "utf8");
		const local = Buffer.alloc(30);
		local.writeUInt32LE(0x04034b50, 0);
		local.writeUInt16LE(20, 4);
		local.writeUInt16LE(0x0800, 6);      // noms en UTF-8
		local.writeUInt16LE(method, 8);
		local.writeUInt16LE(this.time, 10);
		local.writeUInt16LE(this.date, 12);
		local.writeUInt32LE(crc >>> 0, 14);
		local.writeUInt32LE(data.length, 18);
		local.writeUInt32LE(size, 22);
		local.writeUInt16LE(nameBuf.length, 26);
		local.writeUInt16LE(0, 28);
		const at = this.offset;
		this._write(local);
		this._write(nameBuf);
		this._write(data);
		this.central.push({ nameBuf, method, crc, csize: data.length, size, extAttr, madeBy, at });
	}

	file(name, data, mode) {
		const deflated = zlib.deflateRawSync(data, { level: 9 });
		const useDeflate = deflated.length < data.length;
		this.raw(name, useDeflate ? deflated : data, useDeflate ? 8 : 0, zlib.crc32(data), data.length,
			((0o100000 | mode) << 16) >>> 0, 0x0314);
	}

	dir(name) {
		this.raw(name, Buffer.alloc(0), 0, 0, 0, ((0o040755 << 16) | 0x10) >>> 0, 0x0314);
	}

	close() {
		const start = this.offset;
		for (const e of this.central) {
			const h = Buffer.alloc(46);
			h.writeUInt32LE(0x02014b50, 0);
			h.writeUInt16LE(e.madeBy, 4);
			h.writeUInt16LE(20, 6);
			h.writeUInt16LE(0x0800, 8);
			h.writeUInt16LE(e.method, 10);
			h.writeUInt16LE(this.time, 12);
			h.writeUInt16LE(this.date, 14);
			h.writeUInt32LE(e.crc >>> 0, 16);
			h.writeUInt32LE(e.csize, 20);
			h.writeUInt32LE(e.size, 24);
			h.writeUInt16LE(e.nameBuf.length, 28);
			h.writeUInt32LE(e.extAttr >>> 0, 38);
			h.writeUInt32LE(e.at, 42);
			this._write(h);
			this._write(e.nameBuf);
		}
		const end = Buffer.alloc(22);
		end.writeUInt32LE(0x06054b50, 0);
		end.writeUInt16LE(this.central.length, 8);
		end.writeUInt16LE(this.central.length, 10);
		end.writeUInt32LE(this.offset - start, 12);
		end.writeUInt32LE(start, 16);
		this._write(end);
		fs.closeSync(this.fd);
	}
}

// Entrees d'un zip existant (repertoire central), donnees brutes comprises.
function readZip(file) {
	const buf = fs.readFileSync(file);
	let eocd = buf.length - 22;
	while (eocd >= 0 && buf.readUInt32LE(eocd) !== 0x06054b50) eocd--;
	if (eocd < 0) throw new Error("zip illisible : " + file);
	const count = buf.readUInt16LE(eocd + 10);
	let p = buf.readUInt32LE(eocd + 16);
	const out = [];
	for (let k = 0; k < count; k++) {
		const madeBy = buf.readUInt16LE(p + 4);
		const method = buf.readUInt16LE(p + 10);
		const crc = buf.readUInt32LE(p + 16);
		const csize = buf.readUInt32LE(p + 20);
		const size = buf.readUInt32LE(p + 24);
		const nlen = buf.readUInt16LE(p + 28);
		const xlen = buf.readUInt16LE(p + 30);
		const clen = buf.readUInt16LE(p + 32);
		const extAttr = buf.readUInt32LE(p + 38);
		const local = buf.readUInt32LE(p + 42);
		const name = buf.toString("utf8", p + 46, p + 46 + nlen);
		const lnlen = buf.readUInt16LE(local + 26);
		const lxlen = buf.readUInt16LE(local + 28);
		const data = buf.subarray(local + 30 + lnlen + lxlen, local + 30 + lnlen + lxlen + csize);
		out.push({ name, method, crc, size, extAttr, madeBy, data });
		p += 46 + nlen + xlen + clen;
	}
	return out;
}

function addTree(zip, srcDir, prefix) {
	zip.dir(prefix);
	for (const e of fs.readdirSync(srcDir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
		const p = path.join(srcDir, e.name);
		if (e.isDirectory()) addTree(zip, p, prefix + e.name + "/");
		else zip.file(prefix + e.name, fs.readFileSync(p), 0o644);
	}
}

function need(p) {
	if (!fs.existsSync(p)) {
		console.error("package : introuvable " + p + " (make export-windows-share / make export-macos)");
		process.exit(1);
	}
	return p;
}

const README_COMMON = `
JOUER ENSEMBLE EN LIGNE
- Un joueur heberge : JOUER EN LIGNE > HEBERGER. Les autres : JOUER EN LIGNE >
  REJOINDRE, avec l'adresse IP de l'hote.
- Meme maison (meme box) : l'IP locale de l'hote (192.168.x.x), rien a
  regler.
- Par Internet : l'hote ouvre le port UDP 7777 sur sa box (redirection vers
  son PC) et donne son IP publique ; ou tout le monde installe un meme reseau
  virtuel gratuit (ZeroTier, Radmin VPN, Tailscale...) et utilise l'IP de
  l'hote dans ce reseau.
- Tout le monde doit avoir cette meme version du jeu.

MANETTE
Manettes PlayStation, Xbox et compatibles reconnues ; jusqu'a 6 joueurs sur un
meme PC en ecran partage (JOUER EN LOCAL).

Le dossier Assets_Visuels doit rester a cote du jeu (modeles des camions).
`;

const README_WIN = `CRAZY WHEELS - Windows

1. Extraire tout le zip (clic droit > Extraire tout), ne pas lancer depuis le zip.
2. Lancer CrazyWheels.exe (le moteur Godot, signe par son editeur ; il lance
   le jeu contenu dans CrazyWheels.pck, qui doit rester a cote).
3. Si Windows affiche « Windows a protege votre ordinateur » : cliquer sur
   « Informations complementaires », puis « Executer quand meme ».
` + README_COMMON;

const README_MAC = `CRAZY WHEELS - Mac (Intel et Apple Silicon, macOS 11 ou plus recent)

1. Double-cliquer sur le zip pour l'extraire : un dossier CrazyWheels apparait.
   Le ranger ou on veut (Applications, Bureau...), toujours le dossier entier.
2. Une seule fois, avant le premier lancement (le jeu n'est pas signe par
   Apple, sans cette etape macOS le bloque ou le lance sans les camions) :
   - ouvrir le Terminal (Cmd + espace, taper Terminal, Entree) ;
   - taper   xattr -cr   suivi d'un espace (sans appuyer sur Entree) ;
   - glisser le DOSSIER CrazyWheels dans la fenetre du Terminal ;
   - appuyer sur Entree, puis fermer le Terminal.
3. Lancer Crazy Wheels.app (double-clic).
   Si macOS affiche encore un avertissement : clic droit sur Crazy Wheels.app
   > Ouvrir > Ouvrir, ou Reglages Systeme > Confidentialite et securite >
   « Ouvrir quand meme ».
` + README_COMMON;

// BOM : le Bloc-notes lit alors les guillemets « » en UTF-8, sans deviner
function crlf(s) { return Buffer.from("\ufeff" + s.replace(/\n/g, "\r\n"), "utf8"); }

// --- Windows ------------------------------------------------------------------
const winDir = path.join(BUILDS, "share-windows");
need(path.join(winDir, "CrazyWheels.exe"));
const winZip = path.join(BUILDS, "CrazyWheels-Windows.zip");
{
	const z = new ZipWriter(winZip);
	z.dir(TOP);
	z.file(TOP + "CrazyWheels.exe", fs.readFileSync(path.join(winDir, "CrazyWheels.exe")), 0o755);
	z.file(TOP + "CrazyWheels.pck", fs.readFileSync(need(path.join(winDir, "CrazyWheels.pck"))), 0o644);
	addTree(z, need(path.join(winDir, "Assets_Visuels")), TOP + "Assets_Visuels/");
	z.file(TOP + "LISEZ-MOI.txt", crlf(README_WIN), 0o644);
	z.close();
}

// --- Mac ----------------------------------------------------------------------
const macZip = path.join(BUILDS, "CrazyWheels-Mac.zip");
{
	const entries = readZip(need(path.join(BUILDS, "macos", "CrazyWheels.zip")));
	const z = new ZipWriter(macZip);
	z.dir(TOP);
	let app = 0;
	for (const e of entries) {
		// application telle que produite par Godot : donnees et droits recopies
		z.raw(TOP + e.name, e.data, e.method, e.crc, e.size, e.extAttr, e.madeBy);
		app++;
	}
	addTree(z, need(path.join(BUILDS, "macos", "assets", "Assets_Visuels")), TOP + "Assets_Visuels/");
	z.file(TOP + "LISEZ-MOI.txt", Buffer.from(README_MAC, "utf8"), 0o644);
	z.close();
	console.log("Mac : " + app + " entree(s) de l'application recopiees");
}

for (const f of [winZip, macZip]) {
	console.log(path.relative(ROOT, f) + " : " + (fs.statSync(f).size / 1048576).toFixed(1) + " Mo");
}
