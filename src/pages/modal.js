import React from "react";
import styled from "styled-components";
import Img from "gatsby-image";
import ReactPlayer from "react-player";
//import icon from '../images/icon.png'

function Modal({location}) {
  const { state = {} } = location
  return (
    <StyledContainer>
      <StyledGrid>
        <StyledCover>
          <Img fluid={state.img} alt={state.title}  />
        </StyledCover>
        <StyledInfo>
          <h1>{state.artist}</h1>
          <h1>{state.title}</h1>
          <h1>{state.label}</h1>
          <h2>{state.info}</h2>
        </StyledInfo>
        <StyledVideo>
          <div>
            <ReactPlayer wrapper="div" url={state.url} width="260px" height="160px" style={{marginBottom: "-90%"}}/>
          </div>
        </StyledVideo>
      </StyledGrid>
    </StyledContainer>
  );
}

export default Modal;

const StyledContainer = styled.div`
  display: flex;
  justify-content: center;
  align-items: center;
  margin-top: -40px;
  height: 100vh;
  padding: 0 20px 0 20px;
  @media (max-width: 1400px) {
    margin-top: 70px;
  }
  @media (max-width: 600px) {
    margin-top: -180px;
    display: grid;
    box-sizing: border-box;
    overflow: hidden;
  }
`;

const StyledGrid = styled.div`
  display: grid;
  grid-template-columns: 2;
  grid-template-rows: 4;
  gap: 25px;
  @media (max-width: 1400px) {
    padding-top: 90px;
  }
  @media (max-width: 600px) {
    grid-template-columns: 1;
    grid-template-rows: 3;
  }
`;

const StyledInfo = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  margin-bottom: 50px;
  grid-column: 2;
  grid-row: span 4;
  h2 {
    font-family: "Source Code Pro", monospace;
  }
  @media (max-width: 1400px) {
    width: 30vw;
    grid-row: span 2;
    box-shadow: none;
    h1 {
      font-size: 1rem;
    }
    h2 {
      font-size: 1rem;
    }
  }
  @media (max-width: 600px) {
    margin-top: -10px;
    h1 {
      text-align: center;
      font-size: 1rem;
    }
    h2 {
      margin: 10px 0px;
      font-size: 0.3rem;
    }
    grid-column: 1;
    grid-row: 2;
    width: 250px;
  }
`;
const StyledVideo = styled.div`
  div {
    @media (max-width: 1400px) {
      width: 100px;
    }
    @media (max-width: 600px) {
      grid-column: 1;
      grid-row: 3;
      margin-top: -70px;
    }
  }
`;
const StyledCover = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;

  @media (max-width: 1400px) {
    width: 40vw;
    box-shadow: none;
    grid-row: span 2;
  }
  @media (max-width: 600px) {
    grid-column: 1;
    grid-row: 1;
    margin-left: 80px;
    width: 100px;
    box-shadow: 0px 0px 10px 4px #e0e0e0;
    border: 1px solid gold;
  }
`;
