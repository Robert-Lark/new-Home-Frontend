import React from "react";
import Img from "gatsby-image";

function Song({currentSong}) {
	console.log(currentSong.cover.asset)
  return (
    <div className="song-container">
      <Img
        fluid={currentSong.cover.asset.fluid}
		style={{width: "30%", borderRadius: "50%"}}
		alt={currentSong.name}
      />
      <h2>{currentSong.name}</h2>
      <h3>{currentSong.artist}</h3>
    </div>
  );
}

export default Song;
