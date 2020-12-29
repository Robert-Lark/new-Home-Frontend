/* eslint-disable */
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
  libraryStatus, 
  setLibraryStatus
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
    setLibraryStatus(!libraryStatus)
    if (isPlaying) audioRef.current.play();
  };
  return (
    <div
      className={`library-song ${song.active ? "selected" : ""}`}
      onClick={songSelectHandler}
      onKeyDown={null}
      
    >
      <Img
         fluid={song.cover.asset.fluid}
        alt={song.name}
        className="image"
      />
    </div>
  );
}

export default LibrarySong;
