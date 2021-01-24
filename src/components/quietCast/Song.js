import React from "react";
import Img from "gatsby-image";

function Song({currentSong}) {
  return (
    <div className="song-container">
      <Img
        fluid={currentSong.cover.asset.fluid}
        alt={currentSong.name}
        className="image"
      />
      <h2>{currentSong.name}</h2>
    </div>
  );
}

export default Song;


