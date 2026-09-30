import Testing
@testable import FlorestanCore

@Suite struct LibraryMatcherTests {
    let library = LibraryMatcher(songs: [
        ("Heat Waves", "Glass Animals"),
        ("Éire go Deo", "KNEECAP"),
        ("Irish Goodbye (feat. Kae Tempest)", "KNEECAP"),
        ("Here Comes the Sun - Remastered 2009", "The Beatles"),
        ("Schumann: Dichterliebe, Op. 48: 7. Ich grolle nicht", "Barbara Bonney, Antonio Pappano"),
        ("Intro", "The xx"),
    ])

    @Test(arguments: [
        ("Heat Waves (Official Video)", "Glass Animals"),
        ("heat waves", "Glass Animals - Topic"),
        ("Eire Go Deo", "Kneecap"),
        ("Irish Goodbye", "KNEECAP, Kae Tempest"),
        ("Here Comes The Sun (2019 Mix)", "The Beatles"),
        ("Heat Waves Slowed", "Glass Animals"),
        ("Dichterliebe, Op. 48: 7. Ich grolle nicht", "Barbara Bonney"),
        // Distinctive title, artist credited as a channel.
        ("Schumann: Dichterliebe, Op. 48: 7. Ich grolle nicht", "ClassicalVault"),
    ])
    func findsSongsYouHave(_ title: String, _ artist: String) {
        #expect(library.contains(title: title, artist: artist))
    }

    @Test(arguments: [
        ("Intro", "Someone Else"),
        ("Heat", "Glass Animals"),
        ("Gooey", "Glass Animals"),
        ("Sun", "The Beatles"),
    ])
    func leavesOthersAlone(_ title: String, _ artist: String) {
        #expect(!library.contains(title: title, artist: artist))
    }
}
