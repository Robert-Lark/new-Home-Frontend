import React from "react";
import {Link} from "gatsby-plugin-modal-routing";
import {graphql} from "gatsby";
import Img from "gatsby-image";
import styled from "styled-components";
// YOU CAN PROBABLY DESTRUCTURE CONTENT AND REPLACE DATA WITH NODES
function Topten({data}) {
  const content = data.topTen.nodes[0];
  return (
    <StyledContainerDiv>

        <StyledGrid key={content.id}>
          <StyledYear>{content.year}</StyledYear>
          <StyledDescription>{content.description}</StyledDescription>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i1.asset.fluid,
              title: content.title1,
              label: content.label1,
              artist: content.artist1,
              url: content.url1,
              info: content.description1,
            }}
          >
            <StyledTopRow>
              <Img fluid={content.i1.asset.fluid} alt={content.title1} />
              <h2 style={{textAlign: "center"}}>10</h2>
            </StyledTopRow>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i2.asset.fluid,
              title: content.title2,
              label: content.label2,
              artist: content.artist2,
              url: content.url2,
              info: content.description2,
            }}
          >
          <StyledTopRow>
            <Img
              fluid={content.i2.asset.fluid}
              alt={content.title2}
              style={{height: "100%"}}
            />
            <h2 style={{textAlign: "center"}}>9</h2>
          </StyledTopRow>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i3.asset.fluid,
              title: content.title3,
              label: content.label3,
              artist: content.artist3,
              url: content.url3,
              info: content.description3,
            }}
          >
          <StyledTopRow>
            <Img
              fluid={content.i3.asset.fluid}
              alt={content.title3}
              style={{height: "100%"}}
            />
            <h2 style={{textAlign: "center"}}>8</h2>
          </StyledTopRow>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i4.asset.fluid,
              title: content.title4,
              label: content.label4,
              artist: content.artist4,
              url: content.url4,
              info: content.description4,
            }}
          >
          <StyledTopRow>
            <Img
              fluid={content.i4.asset.fluid}
              alt={content.title4}
              style={{height: "100%"}}
            />
            <h2 style={{textAlign: "center"}}>7</h2>
          </StyledTopRow>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i5.asset.fluid,
              title: content.title5,
              label: content.label5,
              artist: content.artist5,
              url: content.url5,
              info: content.description5,
            }}
          >
          <StyledTopRow>
            <Img
              fluid={content.i5.asset.fluid}
              alt={content.title5}
              style={{height: "100%"}}
            />
            <h2 style={{textAlign: "center"}}>6</h2>
          </StyledTopRow>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i6.asset.fluid,
              title: content.title6,
              label: content.label6,
              artist: content.artist6,
              url: content.url6,
              info: content.description6,
            }}
          >
          <StyledFive>
            <Img fluid={content.i6.asset.fluid} alt={content.title6} />
            <h2 style={{textAlign: "center"}}>5</h2>
          </StyledFive>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i7.asset.fluid,
              title: content.title7,
              label: content.label7,
              artist: content.artist7,
              url: content.url7,
              info: content.description7,
            }}
          >
          <StyledFour>
            <Img fluid={content.i7.asset.fluid} alt={content.title7} />
            <h2 style={{textAlign: "center"}}>4</h2>
          </StyledFour>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i8.asset.fluid,
              title: content.title8,
              label: content.label8,
              artist: content.artist8,
              url: content.url8,
              info: content.description8,
            }}
          >
          <StyledThree>
            <Img fluid={content.i8.asset.fluid} alt={content.title8} />
            <h2 style={{textAlign: "center"}}>3</h2>
          </StyledThree>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i9.asset.fluid,
              title: content.title9,
              label: content.label9,
              artist: content.artist9,
              url: content.url9,
              info: content.description9,
            }}
          >
          <StyledSecond>
            <Img fluid={content.i9.asset.fluid} alt={content.title9} />
            <h2 style={{textAlign: "center"}}>2</h2>
          </StyledSecond>
          </Link>
          <Link
            to="/modal"
            asModal
            state={{
              noScroll: true,
              //modal: true,
              img: content.i10.asset.fluid,
              title: content.title10,
              label: content.label10,
              artist: content.artist10,
              url: content.url10,
              info: content.description10,
            }}
          >
          <StyledFirst>
            <Img fluid={content.i10.asset.fluid} alt={content.title10} />
            <h1 style={{textAlign: "center"}}>1</h1>
          </StyledFirst>
          </Link>
        </StyledGrid>

    </StyledContainerDiv>
  );
}

export default Topten;

//MODAL

const StyledContainerDiv = styled.div`
  padding: 40px;
  @media (max-width: 400px) {
   padding: 0px;
  }
`;

const StyledGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  grid-gap: 20px;
  div {
  }
  @media (max-width: 400px) {
    display: grid;
    grid-template-columns: repeat(auto-fit, 300px);
  }
`;
const StyledYear = styled.div`
  margin: 0 10% 0 10%;
  padding: 5% 10% 0% 10%;
  border: none;
  text-align: center;
  font-family: "Cormorant Garamond", serif;
  font-size: 5rem;
  grid-column: span 5;
  @media (max-width: 1375px) {
    font-size: 3.5rem;
  }
  @media (max-width: 1000px) {
    font-size: 3rem;
  }
`;
const StyledDescription = styled.div`
  margin: 0 10% 2% 10%;
  padding: 5% 5% 5% 5%;
  grid-column: span 5;
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 0.5px solid gold;
  border-radius: 20px;
  font-size: 1.5rem;
`;
const StyledTopRow = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 1rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-left: 80px;
  }
`;
const StyledFive = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 1 / span 2;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 1rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-left: 80px;
  }
`;
const StyledFour = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 4 / span 2;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 1rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-left: 80px;
  }
`;
const StyledThree = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 2 / span 3;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 2rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-left: 80px;
  }
`;
const StyledSecond = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 2 / span 3;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 2rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-left: 80px;
  }
`;
const StyledFirst = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: span 5;
  @media (max-width: 1000px) {
    text-align: center;
  font-size: 3rem;
  }
  @media (max-width: 400px) {
    grid-column: 1 / span 1;
    margin-right: -60px;
  }
`;

export const query = graphql`
  query MyQuery {
    topTen: allSanityTest {
      nodes {
        artist1
        artist10
        artist2
        artist3
        artist4
        artist5
        artist6
        artist7
        artist8
        artist9
        description
        description1
        description10
        description2
        description3
        description4
        description5
        description6
        description7
        description8
        description9
        label1
        label10
        label2
        label3
        label4
        label5
        label6
        label7
        label8
        label9
        id
        url1
      url10
      url2
      url3
      url4
      url5
      url6
      url7
      url8
      url910
        title1
        title10
        title2
        title3
        title4
        title5
        title6
        title7
        title8
        title9
        year
        i1 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i2 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i3 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i4 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i5 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i6 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i7 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i8 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i9 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
        i10 {
          asset {
            fluid(maxWidth: 1000) {
              ...GatsbySanityImageFluid
            }
          }
        }
      }
    }
  }
`;
