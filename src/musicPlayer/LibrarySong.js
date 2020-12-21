import React from "react";
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
		setSongs(newSongs)
		if (isPlaying) audioRef.current.play();
	}

	return (
		<div
			className={`library-song ${song.active ? "selected" : ""}`}
			onClick={songSelectHandler}
		>
			<img src={song.cover} alt={song.name} />
		</div>
	);
}

export default LibrarySong;
