import React from "react";
import Img from "gatsby-image";
import styled from "styled-components";

function Interview({current}) {
  //const info = currentInterview.content.nodes;
  console.log(current.artist);
  //console.log(info);

  return (
    <div>
      <h1>{current.artist}</h1>
      <h3>{current.description}</h3>
      <h4>{current.question1}</h4>
      <h5>{current.answer1}</h5>
      <h4>{current.question2}</h4>
      <h5>{current.answer2}</h5>
      <h4>{current.question3}</h4>
      <h5>{current.answer3}</h5>
      <h4>{current.question4}</h4>
      <h5>{current.answer4}</h5>
      <h4>{current.question5}</h4>
      <h5>{current.answer5}</h5>
      <h4>{current.question6}</h4>
      <h5>{current.answer6}</h5>
      <h4>{current.question7}</h4>
      <h5>{current.answer7}</h5>
      <h4>{current.question8}</h4>
      <h5>{current.answer8}</h5>
      <h4>{current.question9}</h4>
      <h5>{current.answer9}</h5>
      <h4>{current.question10}</h4>
      <h5>{current.answer10}</h5>
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
      <h4>{current.question16}</h4>
      <h5>{current.answer16}</h5>
      <h4>{current.question17}</h4>
      <h5>{current.answer17}</h5>
      <h4>{current.question18}</h4>
      <h5>{current.answer18}</h5>
      <h4>{current.question19}</h4>
      <h5>{current.answer19}</h5>
      <h4>{current.question20}</h4>
      <h5>{current.answer20}</h5>
      <Img
        fluid={current.i8.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i8.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i5.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i1.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i2.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i3.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
      <Img
        fluid={current.i4.asset.fluid}
        style={{width: "30%", borderRadius: "50%"}}
        alt={current.name}
      />
    </div>
  );
}

export default Interview;
