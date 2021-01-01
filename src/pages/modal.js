import React from "react";
import styled from "styled-components";
import Img from "gatsby-image";
import ReactPlayer from "react-player";
import {useBreakpoint} from "gatsby-plugin-breakpoints";
// import { getFixedGatsbyImage } from "gatsby-source-sanity";

function Modal({location}) {
  const {state = {}} = location;
  const breakpoints = useBreakpoint();
  return (
    <StyledContainer>
      <StyledGrid>
        <StyledCover>
          <Img fluid={state.img} alt={state.title} />
        </StyledCover>
        <div
          style={{
            width: "50vw",
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
          }}
        >
          <StyledInfo>
            <h1>{state.artist}</h1>
            <h1 style={{marginBottom: "20px"}}>{state.title}</h1>
            <h1 style={{fontSize: "1rem", marginBottom: "20px"}}>
              {state.label}
            </h1>
            <h2>{state.info}</h2>
          </StyledInfo>
          <StyledVideo>
            {breakpoints.xs ? (
              <div>
                <ReactPlayer
                  wrapper="div"
                  url={state.url}
                  // style={{marginBottom: "-90%"}}
                />
              </div>
            ) : breakpoints.sm ? (
              <div>
                <ReactPlayer
                  wrapper="div"
                  url={state.url}

                  // style={{marginBottom: "-90%"}}
                />
              </div>
            ) : breakpoints.md ? (
              <ReactPlayer
                url={state.url}

                // style={{marginBottom: "-90%"}}
              />
            ) : breakpoints.l ? (
              <ReactPlayer
                url={state.url}
                style={{padding: "20px"}}
                // style={{marginTop: "-35%"}}
              />
            ) : (
              <div>
                <ReactPlayer wrapper="div" url={state.url} />
              </div>
            )}
          </StyledVideo>
        </div>
      </StyledGrid>
    </StyledContainer>
  );
}

export default Modal;

const StyledContainer = styled.div`
  /* display: grid;
grid-column: 2;
grid-row: 2; */
  /* display: flex;
  justify-content: center;
  align-items: center;
  margin-top: 90px;
  height: 100vh;
  padding: 0 20px 0 20px;
  @media (max-width: 1400px) {
    margin-top: -60px;
    overflow: visible;
  }
  @media (max-width: 1100px) {
    margin-top: -100px;
  }
  @media (max-width: 950px) {
    margin-top: -50px;
  }
  @media (max-width: 767px) {
    margin-top: -100px;

  }
  @media (max-width: 320px) {
    margin-top: -50%;
  } */
`;

const StyledGrid = styled.div`
padding: 10px;
  display: flex;


  @media (max-width: 767px) {
    display: flex;
    flex-direction: column;
    align-items: center;

    margin-top: -50px;
  }
  @media (max-width: 500px) {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
`;

const StyledInfo = styled.div`
  width: 40vw;

  margin-bottom: 50px;

  h2 {
    font-family: "Source Code Pro", monospace;
  }
  @media (max-width: 767px) {
    width: 80vw;
    h1 {
      text-align: center;
    }
  }

  @media (max-width: 500px) {
    width: 70vw;
    font-size: 0.5rem;
    margin-top: 25px;
    h1 {
      text-align: center;
    }
    h2 {
      text-align: center;
    }
  }
  /* @media (max-width: 1400px) {
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
  @media (max-width: 767px) {
    margin-left: 0px;
    text-align: center;
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
  @media (max-width: 320px) {
    width: 75%;
    margin-left: 7%;
    h1 {
      text-align: center;
      font-size: 0.5rem;
    }
    h2 {
      text-align: center;
    }
  }  */
`;
const StyledVideo = styled.div`
  /* div {
    @media (max-width: 1400px) {
      width: 100px;
    }
    @media (max-width: 1100px) {
margin-top: -400px;
    }
    @media (max-width: 767px) {
      grid-column: 1;
      grid-row: 3;
      margin-top: -70px;
    }
  } */
`;
const StyledCover = styled.div`
  width: 50vw;
  @media (max-width: 800px) {
    display: none;
  }
  /* box-shadow: 0px 0px 10px 4px #e0e0e0;

  @media (max-width: 1400px) {
    width: 40vw;
    box-shadow: none;
    grid-row: span 2;
  }
  @media (max-width: 767px) {
    grid-column: 1;
    grid-row: 1;
    margin-left: 80px;
    width: 100px;
    box-shadow: 0px 0px 10px 4px #e0e0e0;
    margin-left: 31%;
  }
  @media (max-width: 320px) {
    margin-left: 22%;
  } */
`;
