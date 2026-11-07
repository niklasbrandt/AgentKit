// Before / after picture checks: the share of pixels two captures differ in ( the difference's luma over a threshold, 24 of 255 ), decoded and
// compared in headless Chrome, so no image library is needed.
//   node picdiff.mjs <dir A> <dir B> [--out <dir>] [--threshold 24]
//   node picdiff.mjs <file A.png> <file B.png> [--out <dir>] [--threshold 24]
// Compares every PNG of A with the one of the same name in B and prints the share apart. --out also writes per file a sheet: A | B | the pixels
// apart in white, at half size.  Exit code 1 when --fail <percent> is given and any pair is above it.
// Needs puppeteer-core ( resolved from the current directory, so `npm i -D puppeteer-core` in the target repo ) and a Chrome:
// $CHROME, else the macOS default, else a common Linux path.
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

const CHROMES = [ '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium', '/usr/bin/chromium-browser' ];

export const args = () => Object.fromEntries( process.argv.slice( 2 ).reduce( ( acc, v, i, arr ) => v.startsWith( '--' ) ? [ ...acc, [ v.slice( 2 ), arr[ i + 1 ] ] ] : acc, [] ) );

export async function launch() {

	let puppeteer;
	try {

		puppeteer = createRequire( path.join( process.cwd(), 'noop.js' ) )( 'puppeteer-core' );

	} catch ( e ) {

		try {

			puppeteer = ( await import( 'puppeteer-core' ) ).default;

		} catch ( e2 ) {

			console.error( 'puppeteer-core not found. Run `npm i -D puppeteer-core` in the repo you run this from.' );
			process.exit( 2 );

		}

	}

	const executablePath = process.env.CHROME || CHROMES.find( ( f ) => fs.existsSync( f ) );
	if ( ! executablePath ) {

		console.error( 'No Chrome found. Set CHROME=/path/to/chrome.' );
		process.exit( 2 );

	}

	// always headless
	return puppeteer.launch( { executablePath, headless: 'new', args: [ '--no-sandbox', '--mute-audio' ] } );

}

export async function diffPair( browser, fa, fb, { threshold = 24, sheet = null } = {} ) {

	const page = await browser.newPage(), url = ( f ) => 'data:image/png;base64,' + fs.readFileSync( f ).toString( 'base64' );
	const r = await page.evaluate( async ( ua, ub, threshold, wantSheet ) => {

		const load = ( u ) => new Promise( ( res, rej ) => {

			const i = new Image();
			i.onload = () => res( i );
			i.onerror = rej;
			i.src = u;

		} );
		const [ A, B ] = await Promise.all( [ load( ua ), load( ub ) ] ), w = A.width, h = A.height;
		if ( B.width !== w || B.height !== h ) return { size: [ A.width, A.height, B.width, B.height ] };
		const pixels = ( img ) => {

			const c = new OffscreenCanvas( w, h ), x = c.getContext( '2d' );
			x.drawImage( img, 0, 0 );
			return x.getImageData( 0, 0, w, h );

		};

		const a = pixels( A ).data, b = pixels( B ).data, mask = new ImageData( w, h );
		let n = 0;
		for ( let i = 0; i < a.length; i += 4 ) {

			const l = 0.299 * Math.abs( a[ i ] - b[ i ] ) + 0.587 * Math.abs( a[ i + 1 ] - b[ i + 1 ] ) + 0.114 * Math.abs( a[ i + 2 ] - b[ i + 2 ] );
			const on = l > threshold ? 255 : 0;
			if ( on ) n ++;
			mask.data[ i ] = mask.data[ i + 1 ] = mask.data[ i + 2 ] = on;
			mask.data[ i + 3 ] = 255;

		}

		let png = null;
		if ( wantSheet ) {

			const m = new OffscreenCanvas( w, h );
			m.getContext( '2d' ).putImageData( mask, 0, 0 );
			const s = new OffscreenCanvas( w * 3 / 2, h / 2 ), x = s.getContext( '2d' );
			x.drawImage( A, 0, 0, w / 2, h / 2 );
			x.drawImage( B, w / 2, 0, w / 2, h / 2 );
			x.drawImage( m, w, 0, w / 2, h / 2 );
			const blob = await s.convertToBlob( { type: 'image/png' } );
			png = await new Promise( ( res ) => {

				const fr = new FileReader();
				fr.onload = () => res( String( fr.result ).split( ',' )[ 1 ] );
				fr.readAsDataURL( blob );

			} );

		}

		return { pct: 100 * n / ( w * h ), png };

	}, url( fa ), url( fb ), threshold, !! sheet );
	await page.close();
	if ( r.size ) return { pct: NaN, size: r.size };
	if ( sheet && r.png ) fs.writeFileSync( sheet, Buffer.from( r.png, 'base64' ) );
	return { pct: r.pct };

}

if ( process.argv[ 1 ] === fileURLToPath( import.meta.url ) ) {

	const a = args(), [ pa, pb ] = process.argv.slice( 2 ).filter( ( v, i, arr ) => ! v.startsWith( '--' ) && ! ( arr[ i - 1 ] || '' ).startsWith( '--' ) );
	if ( ! pa || ! pb ) {

		console.error( 'usage: node picdiff.mjs <dir|file A> <dir|file B> [--out <dir>] [--threshold 24] [--fail <percent>]' );
		process.exit( 2 );

	}

	if ( a.out ) fs.mkdirSync( a.out, { recursive: true } );
	const pairs = fs.statSync( pa ).isDirectory()
		? fs.readdirSync( pa ).filter( ( f ) => f.endsWith( '.png' ) ).sort().filter( ( f ) => fs.existsSync( path.join( pb, f ) ) ).map( ( f ) => [ f, path.join( pa, f ), path.join( pb, f ) ] )
		: [ [ path.basename( pa ), pa, pb ] ];
	const browser = await launch();
	let worst = 0;
	for ( const [ f, fa, fb ] of pairs ) {

		const r = await diffPair( browser, fa, fb, { threshold: + ( a.threshold || 24 ), sheet: a.out ? path.join( a.out, f ) : null } );
		if ( r.size ) {

			console.log( `${ f.padEnd( 30 ) } sizes differ ( ${ r.size[ 0 ] }x${ r.size[ 1 ] } vs ${ r.size[ 2 ] }x${ r.size[ 3 ] } )` );
			worst = 100;
			continue;

		}

		worst = Math.max( worst, r.pct );
		console.log( `${ f.padEnd( 30 ) } ${ r.pct.toFixed( 2 ).padStart( 6 ) } % apart` );

	}

	await browser.close();
	if ( a.fail !== undefined && worst > + a.fail ) process.exit( 1 );

}
