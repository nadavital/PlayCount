//
//  A√rtworkView.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

struct ArtworkView: View {
    var song: Song
    var body: some View {
        if let image = song.artwork?.image(at: CGSize(width: 50, height: 50)) {
            Image(uiImage: image)
                .resizable()
                .frame(width: 50, height: 50)
                .cornerRadius(4)
        } else {
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                .shadow(radius: 10, x: 5, y: 5)
        }
    }
}

#Preview {
    ArtworkView(song: Song.preview)
}
