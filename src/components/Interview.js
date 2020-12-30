import React from "react";
import Img from "gatsby-image";
import styled from "styled-components";

function Interview({current}) {
  const interviewContent = current;
  console.log(interviewContent);
  return (
    <StyledContainer>
      <StyledTracklistContainer>
        {current.tracklist.map((track) => (
          <p className="tracklist" key={track}>
            {track}
          </p>
        ))}
      </StyledTracklistContainer>
      <StyledAlbumArtGrid>
        {current.albumArt.map((art) => (

            <Img
              fluid={art.asset.fluid}
              alt={current.name}
              className="albumArt"
            />

        ))}
      </StyledAlbumArtGrid>

      <StyledHeader>{current.artist}</StyledHeader>
      <StyledDescription>{current.description}</StyledDescription>
            <StyledArtistImage>
        <Img fluid={current.imageOfArtist.asset.fluid} alt={current.name} />
      </StyledArtistImage>
      <StyledInterviewGrid>
        <h4>{current.question1}</h4>
        <h5>{current.answer1}</h5>

        <Img
          fluid={current.i1.asset.fluid}
          alt={current.name}
          className="image"
        />

        <h4>{current.question2}</h4>
        <h5>{current.answer2}</h5>
        <h4>{current.question3}</h4>
        <h5>{current.answer3}</h5>
        <Img
          fluid={current.i2.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question4}</h4>
        <h5>{current.answer4}</h5>
        <Img
          fluid={current.i3.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question5}</h4>
        <h5>{current.answer5}</h5>
        <Img
          fluid={current.i9.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question6}</h4>
        <h5>{current.answer6}</h5>
        <Img
          fluid={current.i4.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question7}</h4>
        <h5>{current.answer7}</h5>
        <Img
          fluid={current.i5.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question8}</h4>
        <h5>{current.answer8}</h5>
        <Img
          fluid={current.i6.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question9}</h4>
        <h5>{current.answer9}</h5>
        <Img
          fluid={current.i7.asset.fluid}
          alt={current.name}
          className="image"
        />
        <h4>{current.question10}</h4>
        <h5>{current.answer10}</h5>
        <Img
          fluid={current.i8.asset.fluid}
          alt={current.name}
          className="image"
        />
        {/* <div style={current.i10 ? "addQuestions" : "noMoreQuestions"}> */}
        <h4>{current.question11}</h4>
        <h5>{current.answer11}</h5>

        <h4>{current.question12}</h4>
        <h5>{current.answer12}</h5>

        <h4>{current.question13}</h4>
        <h5>{current.answer13}</h5>

        <h4>{current.question14}</h4>
        <h5>{current.answer14}</h5>

        <h4>{current.question15}</h4>
        <h5>{current.answer15}</h5>
        {/* </div> */}
      </StyledInterviewGrid>
      <StyledButton>Return to the top</StyledButton>
    </StyledContainer>
  );
}

const StyledContainer = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  @media screen and (max-width: 375px) {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
`;
const StyledTracklistContainer = styled.div`
  text-align: center;
  padding: 5%;
  p {
    font-family: "Source Code Pro", monospace;
    padding: 0.5rem;
  }
`;
const StyledArtistImage = styled.div`
  padding: 5%;
  @media screen and (max-width: 375px) {
    width: 100%;
  }
`;
const StyledAlbumArtGrid = styled.div`
  width: 100%;
  display: grid;
  grid-auto-flow: column;
  gap: 20px;
  padding: 0 5% 0 5%;
  margin-bottom: 25%;
  .albumArt {
    width: 80%;
    height: 300%;
    @media screen and (max-width: 375px) {
      height: 400%;
      
  }
  }
  @media screen and (max-width: 375px) {
    margin-bottom: 30%;
  }
`;

const StyledHeader = styled.div`
  text-align: center;
  font-size: 5rem;
  font-family: "Source Code Pro", monospace;
  padding: 5%;
  @media screen and (max-width: 375px) {
    font-size: 3rem;
}
`;
const StyledDescription = styled.div`
  text-align: center;
  font-size: 3rem;
  font-family: "Raleway", sans-serif;
  padding: 3%;
  @media screen and (max-width: 375px) {
    font-size: 1rem;
}
`;
const StyledInterviewGrid = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 3%;
  font-size: 3rem;
  @media screen and (max-width: 375px) {
    font-size: 1rem;
}
  h5 {
    margin: 2% 0% 2% 0%;
  }
  .image {
    width: 50vw;
    margin: 5% 0 5% 0;
  }
`;
const StyledButton = styled.div`
  text-align: center;
  width: 100vw;
`;
export default Interview;
