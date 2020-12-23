import React from "react";
import {graphql} from "gatsby";
import Img from "gatsby-image";
import styled from "styled-components";

function topten({data}) {
  const content = data.topTen.nodes;
  console.log(content);
  return (
    <div>
      {content.map((content) => (
        <StyledGrid key={content.id}>
          <StyledYear>{content.year}</StyledYear>
          <StyledDescription>{content.description}</StyledDescription>
          <StyledTen>
            <Img fluid={content.i1.asset.fluid} alt={content.title1} />
            <h4>{content.artist}</h4>
          <h4>{content.title}</h4>
          <h4>{content.label}</h4>
          </StyledTen>
          <StyledNine>
            <Img
              fluid={content.i2.asset.fluid}
              alt={content.title1}
              style={{height: "100%"}}
            />
          </StyledNine>
          <StyledEight>
            <Img
              fluid={content.i3.asset.fluid}
              alt={content.title1}
              style={{height: "100%"}}
            />
          </StyledEight>
          <StyledSeven>
            <Img
              fluid={content.i4.asset.fluid}
              alt={content.title1}
              style={{height: "100%"}}
            />
          </StyledSeven>
          <StyledSix>
            <Img
              fluid={content.i5.asset.fluid}
              alt={content.title1}
              style={{height: "100%"}}
            />
          </StyledSix>
          <StyledFive>
            <Img fluid={content.i6.asset.fluid} alt={content.title1} />
          </StyledFive>
          <StyledFour>
            <Img fluid={content.i7.asset.fluid} alt={content.title1} />
          </StyledFour>
          <StyledThree>
            <Img fluid={content.i8.asset.fluid} alt={content.title1} />
          </StyledThree>
          <StyledSecond>
            <Img fluid={content.i9.asset.fluid} alt={content.title1} />
          </StyledSecond>
          <StyledFirst>
            <Img fluid={content.i10.asset.fluid} alt={content.title1} />
          </StyledFirst>
        </StyledGrid>
      ))}
    </div>
  );
}

export default topten;

const StyledGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  grid-gap: 20px;
  div {
  }
`;
const StyledYear = styled.div`
  margin: 0 10% 0 10%;
  padding: 5% 10% 5% 10%;
  border: none;
  text-align: center;
  font-family: "Cormorant Garamond", serif;
  font-size: 5rem;
  grid-column: span 5;
`;
const StyledDescription = styled.div`
  margin: 0 10% 0 10%;
  padding: 5% 10% 5% 10%;
  grid-column: span 5;
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 0.5px solid gold;
  border-radius: 20px;
`;
const StyledTen = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
`;
const StyledNine = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
`;
const StyledEight = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
`;
const StyledSeven = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
`;
const StyledSix = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
`;
const StyledFive = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 1 / span 2;
`;
const StyledFour = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 4 / span 2;
`;
const StyledThree = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 2 / span 3;
`;
const StyledSecond = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: 2 / span 3;
`;
const StyledFirst = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;
  border: 1px solid gold;
  grid-column: span 5;
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
