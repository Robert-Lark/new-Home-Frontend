import React from "react";
import Img from "gatsby-image";

function LibrarySong({
  song,
  setCurrentSong,
  songs,
  id,
  audioRef,
  isPlaying,
  setSongs,
}) {
  const songSelectHandler = async () => {
    await setCurrentSong(song);
    const newSongs = songs.map((song) => {
      if (song.id === id) {
        return {
          ...song,
          active: true,
        };
      } else {
        return {
          ...song,
          active: false,
        };
      }
    });
    setSongs(newSongs);
    if (isPlaying) audioRef.current.play();
  };
  return (
    <div
      className={`library-song ${song.active ? "selected" : ""}`}
      onClick={songSelectHandler}
    >
      <Img
         fluid={song.cover.asset.fluid}
        alt={song.name}
        style={{width: "100%", borderRadius: "50%"}}
      />
    </div>
  );
}

export default LibrarySong;
